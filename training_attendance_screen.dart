import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/home_navigation.dart';

class TrainingAttendanceScreen extends StatefulWidget {
  final Map<String, dynamic> plan;

  const TrainingAttendanceScreen({
    super.key,
    required this.plan,
  });

  @override
  State<TrainingAttendanceScreen> createState() =>
      _TrainingAttendanceScreenState();
}

class _TrainingAttendanceScreenState
    extends State<TrainingAttendanceScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);
  static const _orange = Color(0xFFFF7A00);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  bool _allowed = false;
  String? _error;

  List<Map<String, dynamic>> _youth = [];
  final Map<String, String> _statusByYouth = {};
  final Map<String, String> _noteByYouth = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Kein Benutzer angemeldet.');
      }

      final profile = await _supabase
          .from('profiles')
          .select('role,approval_status')
          .eq('id', user.id)
          .maybeSingle();

      final trainer =
          profile?['role']?.toString() == 'ausbilder' &&
          profile?['approval_status']?.toString() == 'approved';

      if (!trainer) {
        if (!mounted) return;
        setState(() {
          _allowed = false;
          _loading = false;
        });
        return;
      }

      final results = await Future.wait([
        _supabase
            .from('profiles')
            .select('id,first_name,last_name,approval_status,role')
            .eq('role', 'jugendmitglied')
            .eq('approval_status', 'approved')
            .order('last_name')
            .order('first_name'),
        _supabase
            .from('training_attendance')
            .select('youth_id,status,note')
            .eq('training_plan_id', widget.plan['id']),
      ]);

      final youth = List<Map<String, dynamic>>.from(results[0]);
      final attendance = List<Map<String, dynamic>>.from(results[1]);

      final status = <String, String>{};
      final notes = <String, String>{};

      for (final row in youth) {
        final id = row['id']?.toString();
        if (id != null) {
          status[id] = 'nicht_erfasst';
          notes[id] = '';
        }
      }

      for (final row in attendance) {
        final id = row['youth_id']?.toString();
        if (id == null) continue;

        status[id] = row['status']?.toString() ?? 'nicht_erfasst';
        notes[id] = row['note']?.toString() ?? '';
      }

      if (!mounted) return;

      setState(() {
        _allowed = true;
        _youth = youth;
        _statusByYouth
          ..clear()
          ..addAll(status);
        _noteByYouth
          ..clear()
          ..addAll(notes);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _name(Map<String, dynamic> youth) {
    final first = youth['first_name']?.toString().trim() ?? '';
    final last = youth['last_name']?.toString().trim() ?? '';
    final value = '$first $last'.trim();

    return value.isEmpty ? 'Jugendmitglied' : value;
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return 'Kein Datum';

    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  String _time(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';

    final parts = raw.split(':');
    if (parts.length < 2) return raw;

    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  String _timeRange() {
    final start = _time(widget.plan['start_time']);
    final end = _time(widget.plan['end_time']);

    if (start.isEmpty) return '';
    if (end.isEmpty) return '$start Uhr';

    return '$start – $end Uhr';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'anwesend':
        return _green;
      case 'entschuldigt':
        return _orange;
      case 'abwesend':
        return _red;
      default:
        return const Color(0xFF98A2B3);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'anwesend':
        return Icons.check_circle_outline;
      case 'entschuldigt':
        return Icons.event_busy_outlined;
      case 'abwesend':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'anwesend':
        return 'Anwesend';
      case 'entschuldigt':
        return 'Entschuldigt';
      case 'abwesend':
        return 'Abwesend';
      default:
        return 'Nicht erfasst';
    }
  }

  int _count(String status) {
    return _statusByYouth.values.where((value) => value == status).length;
  }

  void _setAll(String status) {
    setState(() {
      for (final youth in _youth) {
        final id = youth['id']?.toString();
        if (id != null) {
          _statusByYouth[id] = status;
        }
      }
    });
  }

  Future<void> _editNote(Map<String, dynamic> youth) async {
    final id = youth['id']?.toString();
    if (id == null) return;

    final controller = TextEditingController(
      text: _noteByYouth[id] ?? '',
    );

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Bemerkung – ${_name(youth)}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Optionale Bemerkung',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim(),
            ),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (value == null || !mounted) return;

    setState(() {
      _noteByYouth[id] = value;
    });
  }

  Future<void> _save() async {
    if (_saving) return;

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    try {
      final upserts = <Map<String, dynamic>>[];
      final removeYouthIds = <String>[];

      for (final youth in _youth) {
        final youthId = youth['id']?.toString();
        if (youthId == null) continue;

        final status = _statusByYouth[youthId] ?? 'nicht_erfasst';

        if (status == 'nicht_erfasst') {
          removeYouthIds.add(youthId);
          continue;
        }

        final note = (_noteByYouth[youthId] ?? '').trim();

        upserts.add({
          'training_plan_id': widget.plan['id'],
          'youth_id': youthId,
          'status': status,
          'note': note.isEmpty ? null : note,
          'marked_by': user.id,
          'marked_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      if (upserts.isNotEmpty) {
        await _supabase.from('training_attendance').upsert(
              upserts,
              onConflict: 'training_plan_id,youth_id',
            );
      }

      for (final youthId in removeYouthIds) {
        await _supabase
            .from('training_attendance')
            .delete()
            .eq('training_plan_id', widget.plan['id'])
            .eq('youth_id', youthId);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anwesenheit gespeichert.'),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Speichern fehlgeschlagen: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_allowed) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Dieser Bereich ist ausschließlich für Ausbilder freigegeben.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final title =
        widget.plan['topic']?.toString().trim().isNotEmpty == true
            ? widget.plan['topic'].toString()
            : widget.plan['title']?.toString() ?? 'Ausbildung';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Anwesenheit'),
        actions: [
          IconButton(
            tooltip: 'Zur Startseite',
            onPressed: () => HomeNavigation.goHome(context),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_navy, _blue],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AUSBILDUNG',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    '${_date(widget.plan['training_date'])}'
                    '${_timeRange().isEmpty ? '' : ' · ${_timeRange()}'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ((widget.plan['location']?.toString() ?? '')
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      widget.plan['location'].toString(),
                      style: const TextStyle(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SummaryBox(
                    value: '${_count('anwesend')}',
                    label: 'Anwesend',
                    color: _green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryBox(
                    value: '${_count('entschuldigt')}',
                    label: 'Entschuldigt',
                    color: _orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryBox(
                    value: '${_count('abwesend')}',
                    label: 'Abwesend',
                    color: _red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _setAll('anwesend'),
                  icon: const Icon(Icons.done_all),
                  label: const Text('Alle anwesend'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _setAll('nicht_erfasst'),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Zurücksetzen'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: _red),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              '${_youth.length} Jugendmitglieder',
              style: const TextStyle(
                color: _navy,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            if (_youth.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Es sind keine freigegebenen Jugendmitglieder vorhanden.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ..._youth.map((youth) {
                final youthId = youth['id']?.toString() ?? '';
                final status =
                    _statusByYouth[youthId] ?? 'nicht_erfasst';
                final note = (_noteByYouth[youthId] ?? '').trim();
                final color = _statusColor(status);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: color.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Icon(
                              _statusIcon(status),
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              _name(youth),
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Bemerkung',
                            onPressed: () => _editNote(youth),
                            icon: Icon(
                              note.isEmpty
                                  ? Icons.notes_outlined
                                  : Icons.sticky_note_2,
                              color: note.isEmpty ? null : _blue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: InputDecoration(
                          labelText: 'Status',
                          prefixIcon: Icon(
                            _statusIcon(status),
                            color: color,
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'nicht_erfasst',
                            child: Text('Nicht erfasst'),
                          ),
                          DropdownMenuItem(
                            value: 'anwesend',
                            child: Text('Anwesend'),
                          ),
                          DropdownMenuItem(
                            value: 'entschuldigt',
                            child: Text('Entschuldigt'),
                          ),
                          DropdownMenuItem(
                            value: 'abwesend',
                            child: Text('Abwesend'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _statusByYouth[youthId] = value;
                          });
                        },
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Bemerkung: $note',
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        backgroundColor: _red,
        foregroundColor: Colors.white,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save_outlined),
        label: Text(_saving ? 'Speichern...' : 'Speichern'),
      ),
    );
  }
}

class TrainingRecordsScreen extends StatefulWidget {
  const TrainingRecordsScreen({super.key});

  @override
  State<TrainingRecordsScreen> createState() =>
      _TrainingRecordsScreenState();
}

class _TrainingRecordsScreenState extends State<TrainingRecordsScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);
  static const _orange = Color(0xFFFF7A00);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _allowed = false;
  String? _error;

  List<Map<String, dynamic>> _youth = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _attendance = [];

  int? _selectedYear;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Kein Benutzer angemeldet.');
      }

      final own = await _supabase
          .from('profiles')
          .select('role,approval_status')
          .eq('id', user.id)
          .maybeSingle();

      final trainer =
          own?['role']?.toString() == 'ausbilder' &&
          own?['approval_status']?.toString() == 'approved';

      if (!trainer) {
        if (!mounted) return;
        setState(() {
          _allowed = false;
          _loading = false;
        });
        return;
      }

      final results = await Future.wait([
        _supabase
            .from('profiles')
            .select('id,first_name,last_name')
            .eq('role', 'jugendmitglied')
            .eq('approval_status', 'approved')
            .order('last_name')
            .order('first_name'),
        _supabase
            .from('training_plans')
            .select(
              'id,title,topic,training_date,start_time,end_time,location',
            )
            .order('training_date', ascending: false),
        _supabase
            .from('training_attendance')
            .select(
              'training_plan_id,youth_id,status,note,marked_at',
            ),
      ]);

      if (!mounted) return;

      setState(() {
        _allowed = true;
        _youth = List<Map<String, dynamic>>.from(results[0]);
        _plans = List<Map<String, dynamic>>.from(results[1]);
        _attendance = List<Map<String, dynamic>>.from(results[2]);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _name(Map<String, dynamic> youth) {
    final first = youth['first_name']?.toString().trim() ?? '';
    final last = youth['last_name']?.toString().trim() ?? '';
    final value = '$first $last'.trim();

    return value.isEmpty ? 'Jugendmitglied' : value;
  }

  int? _yearOfPlan(String planId) {
    final plan = _planById(planId);
    final date = DateTime.tryParse(plan?['training_date']?.toString() ?? '');
    return date?.year;
  }

  Map<String, dynamic>? _planById(String id) {
    for (final plan in _plans) {
      if (plan['id']?.toString() == id) return plan;
    }
    return null;
  }

  List<int> get _availableYears {
    final years = <int>{};

    for (final plan in _plans) {
      final date = DateTime.tryParse(
        plan['training_date']?.toString() ?? '',
      );
      if (date != null) years.add(date.year);
    }

    final result = years.toList()..sort((a, b) => b.compareTo(a));
    return result;
  }

  List<Map<String, dynamic>> _recordsFor(String youthId) {
    final records = _attendance
        .where((row) {
          if (row['youth_id']?.toString() != youthId) return false;

          if (_selectedYear == null) return true;

          final planId = row['training_plan_id']?.toString();
          if (planId == null) return false;

          return _yearOfPlan(planId) == _selectedYear;
        })
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    records.sort((a, b) {
      final aPlan = _planById(a['training_plan_id']?.toString() ?? '');
      final bPlan = _planById(b['training_plan_id']?.toString() ?? '');

      final aDate = DateTime.tryParse(
            aPlan?['training_date']?.toString() ?? '',
          ) ??
          DateTime(1900);
      final bDate = DateTime.tryParse(
            bPlan?['training_date']?.toString() ?? '',
          ) ??
          DateTime(1900);

      return bDate.compareTo(aDate);
    });

    return records;
  }

  int _countStatus(
    List<Map<String, dynamic>> records,
    String status,
  ) {
    return records
        .where((row) => row['status']?.toString() == status)
        .length;
  }

  int _attendancePercent(List<Map<String, dynamic>> records) {
    if (records.isEmpty) return 0;

    final present = _countStatus(records, 'anwesend');
    return ((present / records.length) * 100).round();
  }

  double _attendedHours(List<Map<String, dynamic>> records) {
    var minutes = 0;

    for (final record in records) {
      if (record['status']?.toString() != 'anwesend') continue;

      final plan =
          _planById(record['training_plan_id']?.toString() ?? '');
      if (plan == null) continue;

      final start = _minutes(plan['start_time']);
      final end = _minutes(plan['end_time']);

      if (start != null && end != null && end > start) {
        minutes += end - start;
      }
    }

    return minutes / 60;
  }

  int? _minutes(dynamic value) {
    final raw = value?.toString() ?? '';
    final parts = raw.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) return null;

    return hour * 60 + minute;
  }

  Color _rateColor(int percent) {
    if (percent >= 80) return _green;
    if (percent >= 60) return _orange;
    return _red;
  }

  Future<void> _openDetails(Map<String, dynamic> youth) async {
    final youthId = youth['id']?.toString();
    if (youthId == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _YouthTrainingRecordDetail(
          youth: youth,
          records: _recordsFor(youthId),
          plans: _plans,
          selectedYear: _selectedYear,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_allowed) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Dieser Bereich ist ausschließlich für Ausbilder freigegeben.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Ausbildungsnachweise'),
        actions: [
          IconButton(
            tooltip: 'Zur Startseite',
            onPressed: () => HomeNavigation.goHome(context),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_navy, _blue],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    color: Colors.white,
                    size: 34,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Anwesenheit und Ausbildungsfortschritt der Jugendmitglieder',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: _selectedYear,
              decoration: const InputDecoration(
                labelText: 'Zeitraum',
                prefixIcon: Icon(Icons.calendar_month_outlined),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Alle Jahre'),
                ),
                ..._availableYears.map(
                  (year) => DropdownMenuItem<int?>(
                    value: year,
                    child: Text('$year'),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _selectedYear = value);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: _red),
              ),
            ],
            const SizedBox(height: 18),
            if (_youth.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Keine Jugendmitglieder vorhanden.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ..._youth.map((youth) {
                final youthId = youth['id']?.toString() ?? '';
                final records = _recordsFor(youthId);

                final present = _countStatus(records, 'anwesend');
                final excused = _countStatus(records, 'entschuldigt');
                final absent = _countStatus(records, 'abwesend');
                final percent = _attendancePercent(records);
                final hours = _attendedHours(records);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFE3E8EE),
                    ),
                  ),
                  child: InkWell(
                    onTap: () => _openDetails(youth),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFFEAF2FB),
                                child: Icon(
                                  Icons.person_outline,
                                  color: _blue,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  _name(youth),
                                  style: const TextStyle(
                                    color: _navy,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFF98A2B3),
                              ),
                            ],
                          ),
                          const SizedBox(height: 13),
                          Row(
                            children: [
                              Expanded(
                                child: _MiniStat(
                                  value: '$present',
                                  label: 'anwesend',
                                  color: _green,
                                ),
                              ),
                              Expanded(
                                child: _MiniStat(
                                  value: '$excused',
                                  label: 'entschuldigt',
                                  color: _orange,
                                ),
                              ),
                              Expanded(
                                child: _MiniStat(
                                  value: '$absent',
                                  label: 'abwesend',
                                  color: _red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Text(
                                'Anwesenheit',
                                style: TextStyle(
                                  color: Color(0xFF667085),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                records.isEmpty ? '–' : '$percent %',
                                style: TextStyle(
                                  color: records.isEmpty
                                      ? const Color(0xFF98A2B3)
                                      : _rateColor(percent),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          if (records.isNotEmpty) ...[
                            const SizedBox(height: 7),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: percent / 100,
                                minHeight: 8,
                                backgroundColor: const Color(0xFFE8EDF3),
                                color: _rateColor(percent),
                              ),
                            ),
                          ],
                          if (hours > 0) ...[
                            const SizedBox(height: 9),
                            Text(
                              'Besuchte Ausbildungszeit: '
                              '${hours.toStringAsFixed(hours % 1 == 0 ? 0 : 1)} Std.',
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _YouthTrainingRecordDetail extends StatelessWidget {
  static const _navy = Color(0xFF0A1F44);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);
  static const _orange = Color(0xFFFF7A00);

  final Map<String, dynamic> youth;
  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> plans;
  final int? selectedYear;

  const _YouthTrainingRecordDetail({
    required this.youth,
    required this.records,
    required this.plans,
    required this.selectedYear,
  });

  String _name() {
    final first = youth['first_name']?.toString().trim() ?? '';
    final last = youth['last_name']?.toString().trim() ?? '';
    final value = '$first $last'.trim();

    return value.isEmpty ? 'Jugendmitglied' : value;
  }

  Map<String, dynamic>? _plan(String id) {
    for (final plan in plans) {
      if (plan['id']?.toString() == id) return plan;
    }
    return null;
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return 'Kein Datum';

    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  String _time(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';

    final parts = raw.split(':');
    if (parts.length < 2) return raw;

    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'anwesend':
        return _green;
      case 'entschuldigt':
        return _orange;
      default:
        return _red;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'anwesend':
        return 'Anwesend';
      case 'entschuldigt':
        return 'Entschuldigt';
      default:
        return 'Abwesend';
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'anwesend':
        return Icons.check_circle_outline;
      case 'entschuldigt':
        return Icons.event_busy_outlined;
      default:
        return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Text(_name()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            selectedYear == null
                ? 'Ausbildungsnachweis – alle Jahre'
                : 'Ausbildungsnachweis $selectedYear',
            style: const TextStyle(
              color: _navy,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          if (records.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Für diesen Zeitraum wurden noch keine Anwesenheiten erfasst.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ...records.map((record) {
              final plan = _plan(
                record['training_plan_id']?.toString() ?? '',
              );
              if (plan == null) return const SizedBox.shrink();

              final status =
                  record['status']?.toString() ?? 'abwesend';
              final topic =
                  plan['topic']?.toString().trim().isNotEmpty == true
                      ? plan['topic'].toString()
                      : plan['title']?.toString() ?? 'Ausbildung';
              final start = _time(plan['start_time']);
              final end = _time(plan['end_time']);
              final note = record['note']?.toString().trim() ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _statusColor(status).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          _statusColor(status).withValues(alpha: 0.12),
                      child: Icon(
                        _statusIcon(status),
                        color: _statusColor(status),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topic,
                            style: const TextStyle(
                              color: _navy,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_date(plan['training_date'])}'
                            '${start.isEmpty ? '' : ' · $start${end.isEmpty ? '' : ' – $end'} Uhr'}',
                            style: const TextStyle(
                              color: Color(0xFF667085),
                            ),
                          ),
                          if ((plan['location']?.toString() ?? '')
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              plan['location'].toString(),
                              style: const TextStyle(
                                color: Color(0xFF667085),
                              ),
                            ),
                          ],
                          const SizedBox(height: 7),
                          Text(
                            _statusLabel(status),
                            style: TextStyle(
                              color: _statusColor(status),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              'Bemerkung: $note',
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _SummaryBox({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _MiniStat({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
