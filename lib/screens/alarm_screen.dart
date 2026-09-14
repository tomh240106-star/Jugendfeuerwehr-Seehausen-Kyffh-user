import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF16A34A);
  static const _orange = Color(0xFFFF8A00);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  bool _isYouth = false;
  bool _sending = false;
  String? _error;

  Map<String, dynamic>? _activeAlarm;
  List<Map<String, dynamic>> _responses = [];
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _history = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshActiveOnly(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Kein Benutzer angemeldet.');

      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final role = profile?['role']?.toString() ?? '';
      final isTrainer = role == 'ausbilder';
      final isYouth = role == 'jugendmitglied';

      if (!isTrainer && !isYouth) {
        if (!mounted) return;
        setState(() {
          _isTrainer = false;
          _isYouth = false;
          _loading = false;
        });
        return;
      }

      final alarmRows = await _supabase
          .from('alarms')
          .select()
          .order('created_at', ascending: false)
          .limit(15);

      final alarms = List<Map<String, dynamic>>.from(alarmRows);
      Map<String, dynamic>? active;
      for (final alarm in alarms) {
        if (alarm['is_active'] == true) {
          active = alarm;
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _isTrainer = isTrainer;
        _isYouth = isYouth;
        _activeAlarm = active;
        _history = alarms.where((a) => a['is_active'] != true).toList();
        _loading = false;
        _error = null;
      });

      await _loadResponses();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _refreshActiveOnly() async {
    if (!_isTrainer && !_isYouth) return;

    try {
      final rows = await _supabase
          .from('alarms')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1);

      final active = rows.isEmpty
          ? null
          : Map<String, dynamic>.from(rows.first);

      if (!mounted) return;
      setState(() => _activeAlarm = active);
      await _loadResponses();
    } catch (_) {}
  }

  Future<void> _loadResponses() async {
    final alarm = _activeAlarm;
    if (alarm == null) {
      if (mounted) setState(() => _responses = []);
      return;
    }

    try {
      final responseRows = await _supabase
          .from('alarm_responses')
          .select('id,alarm_id,user_id,response,responded_at')
          .eq('alarm_id', alarm['id']);

      final responses = List<Map<String, dynamic>>.from(responseRows);

      List<Map<String, dynamic>> profiles = [];
      if (_isTrainer) {
        final profileRows = await _supabase
            .from('profiles')
            .select('id,first_name,last_name,role')
            .eq('role', 'jugendmitglied')
            .order('last_name');
        profiles = List<Map<String, dynamic>>.from(profileRows);
      }

      if (!mounted) return;
      setState(() {
        _responses = responses;
        _profiles = profiles;
      });
    } catch (_) {}
  }

  Future<void> _createAlarm() async {
    if (!_isTrainer || _sending) return;

    final titleController = TextEditingController(
      text: 'Übungsalarm Jugendfeuerwehr',
    );
    final locationController = TextEditingController(
      text: 'Feuerwehrgerätehaus',
    );
    final descriptionController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alarm auslösen'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Nur Jugendmitglieder und Ausbilder erhalten diesen Alarm.',
                style: TextStyle(
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Titel',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: 'Treffpunkt',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Beschreibung (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isEmpty) return;

              Navigator.pop(
                context,
                {
                  'title': title,
                  'location': locationController.text.trim(),
                  'description': descriptionController.text.trim(),
                },
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: _red,
            ),
            icon: const Icon(Icons.notifications_active),
            label: const Text('Alarm auslösen'),
          ),
        ],
      ),
    );

    titleController.dispose();
    locationController.dispose();
    descriptionController.dispose();

    if (result == null) return;

    setState(() => _sending = true);

    try {
      // Es soll gleichzeitig nur einen aktiven Jugendfeuerwehr-Alarm geben.
      final existing = await _supabase
          .from('alarms')
          .select('id')
          .eq('is_active', true)
          .limit(1);

      if (existing.isNotEmpty) {
        throw Exception(
          'Es ist bereits ein Alarm aktiv. Beende ihn zuerst.',
        );
      }

      final user = _supabase.auth.currentUser!;
      final inserted = await _supabase
          .from('alarms')
          .insert({
            'title': result['title'],
            'location': result['location']!.isEmpty
                ? null
                : result['location'],
            'description': result['description']!.isEmpty
                ? null
                : result['description'],
            'created_by': user.id,
            'is_active': true,
          })
          .select()
          .single();

      final alarm = Map<String, dynamic>.from(inserted);

      final response = await _supabase.functions.invoke(
        'send-alarm',
        body: {
          'alarm_id': alarm['id'],
        },
      );

      if (response.status >= 400) {
        throw Exception(
          'Alarm wurde gespeichert, Push konnte aber nicht versendet werden.',
        );
      }

      if (!mounted) return;

      setState(() => _activeAlarm = alarm);
      await _loadResponses();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alarm wurde ausgelöst. Jugendmitglieder und Ausbilder wurden benachrichtigt.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alarm konnte nicht ausgelöst werden: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _respond(String response) async {
    if (!_isYouth || _activeAlarm == null || _sending) return;

    setState(() => _sending = true);

    try {
      final user = _supabase.auth.currentUser!;

      await _supabase.from('alarm_responses').upsert(
        {
          'alarm_id': _activeAlarm!['id'],
          'user_id': user.id,
          'response': response,
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'alarm_id,user_id',
      );

      await _loadResponses();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Antwort gespeichert: ${_responseLabel(response)}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Antwort konnte nicht gespeichert werden: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _endAlarm() async {
    if (!_isTrainer || _activeAlarm == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alarm beenden?'),
        content: const Text(
          'Der aktive Jugendfeuerwehr-Alarm wird beendet und in die Historie verschoben.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: _red,
            ),
            child: const Text('Alarm beenden'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _supabase
          .from('alarms')
          .update({
            'is_active': false,
            'ended_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _activeAlarm!['id']);

      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alarm konnte nicht beendet werden: $e'),
        ),
      );
    }
  }

  String _responseLabel(String? response) {
    switch (response) {
      case 'in_5_min':
        return 'Bin in 5 Min. da';
      case 'in_10_min':
        return 'Bin in 10 Min. da';
      case 'spaeter':
        return 'Bin später da';
      case 'an_wache':
        return 'Bin an der Wache';
      case 'kann_nicht':
        return 'Kann nicht kommen';
      default:
        return 'Noch keine Antwort';
    }
  }

  Color _responseColor(String? response) {
    switch (response) {
      case 'in_5_min':
        return _blue;
      case 'in_10_min':
        return _orange;
      case 'spaeter':
        return const Color(0xFF7C3AED);
      case 'an_wache':
        return _green;
      case 'kann_nicht':
        return _red;
      default:
        return const Color(0xFF98A2B3);
    }
  }

  String? _myResponse() {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    for (final response in _responses) {
      if (response['user_id']?.toString() == user.id) {
        return response['response']?.toString();
      }
    }
    return null;
  }

  Map<String, dynamic>? _responseForUser(String userId) {
    for (final response in _responses) {
      if (response['user_id']?.toString() == userId) return response;
    }
    return null;
  }

  int _count(String value) =>
      _responses.where((r) => r['response'] == value).length;

  String _personName(Map<String, dynamic> profile) {
    final first = profile['first_name']?.toString().trim() ?? '';
    final last = profile['last_name']?.toString().trim() ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Jugendmitglied' : name;
  }

  String _formatDate(dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.${dt.year} · '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')} Uhr';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isTrainer && !_isYouth) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F5F7),
        appBar: AppBar(title: const Text('Alarm')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Der Alarm-Bereich ist nur für Jugendmitglieder und Ausbilder verfügbar.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_red, Color(0xFF9B0710)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.notifications_active,
                          color: _red,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Jugendfeuerwehr-Alarm',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Übungs- und Organisationsalarm',
                              style: TextStyle(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isTrainer && _activeAlarm == null)
                        IconButton(
                          onPressed: _sending ? null : _createAlarm,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _red,
                          ),
                          icon: const Icon(Icons.add_alert),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: _red),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
              child: Column(
                children: [
                  if (_activeAlarm == null)
                    _NoActiveAlarm(
                      isTrainer: _isTrainer,
                      onCreate: _createAlarm,
                    )
                  else ...[
                    _ActiveAlarmCard(
                      alarm: _activeAlarm!,
                      formatDate: _formatDate,
                    ),
                    const SizedBox(height: 14),
                    if (_isYouth)
                      _YouthResponsePanel(
                        currentResponse: _myResponse(),
                        sending: _sending,
                        onRespond: _respond,
                        responseLabel: _responseLabel,
                      ),
                    if (_isTrainer)
                      _TrainerOverview(
                        profiles: _profiles,
                        responseForUser: _responseForUser,
                        count5: _count('in_5_min'),
                        count10: _count('in_10_min'),
                        countLater: _count('spaeter'),
                        countStation: _count('an_wache'),
                        countNo: _count('kann_nicht'),
                        responseLabel: _responseLabel,
                        responseColor: _responseColor,
                        personName: _personName,
                        onEndAlarm: _endAlarm,
                      ),
                  ],
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Letzte Alarme',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._history.take(5).map(
                      (alarm) => Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.history,
                            color: _red,
                          ),
                          title: Text(
                            alarm['title']?.toString() ?? 'Alarm',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(_formatDate(alarm['created_at'])),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoActiveAlarm extends StatelessWidget {
  final bool isTrainer;
  final VoidCallback onCreate;

  const _NoActiveAlarm({
    required this.isTrainer,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3E8EE)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.notifications_none,
            size: 68,
            color: Color(0xFF98A2B3),
          ),
          const SizedBox(height: 14),
          const Text(
            'Kein aktiver Alarm',
            style: TextStyle(
              color: Color(0xFF0A1F44),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Aktuell wurde kein Jugendfeuerwehr-Alarm ausgelöst.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF667085)),
          ),
          if (isTrainer) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE30613),
              ),
              icon: const Icon(Icons.add_alert),
              label: const Text('Alarm auslösen'),
            ),
          ],
        ],
      ),
    );
  }
}

String _alarmActiveFor(dynamic value) {
  final created = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (created == null) return '';

  final diff = DateTime.now().difference(created);
  if (diff.inMinutes < 1) return 'Gerade ausgelöst';
  if (diff.inHours < 1) return 'Seit ${diff.inMinutes} Min. aktiv';

  final hours = diff.inHours;
  final minutes = diff.inMinutes.remainder(60);
  return minutes == 0
      ? 'Seit $hours Std. aktiv'
      : 'Seit $hours Std. $minutes Min. aktiv';
}

class _ActiveAlarmCard extends StatelessWidget {
  final Map<String, dynamic> alarm;
  final String Function(dynamic) formatDate;

  const _ActiveAlarmCard({
    required this.alarm,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFE30613);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: red,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 6),
            color: Color(0x22E30613),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.notifications_active,
                color: Colors.white,
              ),
              SizedBox(width: 8),
              Text(
                'AKTIVER ALARM',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            alarm['title']?.toString() ?? 'Jugendfeuerwehr-Alarm',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          if ((alarm['description'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              alarm['description'].toString(),
              style: const TextStyle(
                color: Colors.white,
                height: 1.35,
              ),
            ),
          ],
          if ((alarm['location'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    alarm['location'].toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.timer_outlined,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                _alarmActiveFor(alarm['created_at']),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ausgelöst: ${formatDate(alarm['created_at'])}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _YouthResponsePanel extends StatelessWidget {
  final String? currentResponse;
  final bool sending;
  final Future<void> Function(String) onRespond;
  final String Function(String?) responseLabel;

  const _YouthResponsePanel({
    required this.currentResponse,
    required this.sending,
    required this.onRespond,
    required this.responseLabel,
  });

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A1F44);

    final options = <(String, String, IconData, Color)>[
      ('in_5_min', 'Bin in 5 Min. da', Icons.directions_run, Color(0xFF0B4EA2)),
      ('in_10_min', 'Bin in 10 Min. da', Icons.schedule, Color(0xFFFF8A00)),
      ('spaeter', 'Bin später da', Icons.more_time, Color(0xFF7C3AED)),
      ('an_wache', 'Bin an der Wache', Icons.home_work_outlined, Color(0xFF16A34A)),
      ('kann_nicht', 'Kann nicht kommen', Icons.close, Color(0xFFE30613)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3E8EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Deine Rückmeldung',
            style: TextStyle(
              color: navy,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (currentResponse != null) ...[
            const SizedBox(height: 6),
            Text(
              'Aktuell: ${responseLabel(currentResponse)}',
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...options.map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: sending
                      ? null
                      : () => onRespond(option.$1),
                  style: FilledButton.styleFrom(
                    backgroundColor: option.$4,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  icon: Icon(option.$3),
                  label: Text(
                    option.$2,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainerOverview extends StatelessWidget {
  final List<Map<String, dynamic>> profiles;
  final Map<String, dynamic>? Function(String) responseForUser;
  final int count5;
  final int count10;
  final int countLater;
  final int countStation;
  final int countNo;
  final String Function(String?) responseLabel;
  final Color Function(String?) responseColor;
  final String Function(Map<String, dynamic>) personName;
  final VoidCallback onEndAlarm;

  const _TrainerOverview({
    required this.profiles,
    required this.responseForUser,
    required this.count5,
    required this.count10,
    required this.countLater,
    required this.countStation,
    required this.countNo,
    required this.responseLabel,
    required this.responseColor,
    required this.personName,
    required this.onEndAlarm,
  });

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A1F44);
    const red = Color(0xFFE30613);

    final answered = count5 + count10 + countLater + countStation + countNo;
    final open = (profiles.length - answered).clamp(0, profiles.length);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE3E8EE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rückmeldungen',
                style: TextStyle(
                  color: navy,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CountChip(label: '5 Min.', count: count5, color: Color(0xFF0B4EA2)),
                  _CountChip(label: '10 Min.', count: count10, color: Color(0xFFFF8A00)),
                  _CountChip(label: 'Später', count: countLater, color: Color(0xFF7C3AED)),
                  _CountChip(label: 'Wache', count: countStation, color: Color(0xFF16A34A)),
                  _CountChip(label: 'Kann nicht', count: countNo, color: red),
                  _CountChip(label: 'Offen', count: open, color: Color(0xFF98A2B3)),
                ],
              ),
              const SizedBox(height: 18),
              ...([...profiles]..sort((a, b) {
                int priority(Map<String, dynamic> p) {
                  final value =
                      responseForUser(p['id'].toString())?['response']?.toString();
                  switch (value) {
                    case 'an_wache':
                      return 0;
                    case 'in_5_min':
                      return 1;
                    case 'in_10_min':
                      return 2;
                    case 'spaeter':
                      return 3;
                    case 'kann_nicht':
                      return 4;
                    default:
                      return 5;
                  }
                }

                final byStatus = priority(a).compareTo(priority(b));
                if (byStatus != 0) return byStatus;
                return personName(a).compareTo(personName(b));
              })).map((profile) {
                final response =
                    responseForUser(profile['id'].toString());
                final value = response?['response']?.toString();
                final color = responseColor(value);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(
                          value == 'an_wache'
                              ? Icons.home_work_outlined
                              : Icons.person,
                          size: 18,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          personName(profile),
                          style: const TextStyle(
                            color: navy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        responseLabel(value),
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onEndAlarm,
            style: FilledButton.styleFrom(
              backgroundColor: navy,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Alarm beenden'),
          ),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
