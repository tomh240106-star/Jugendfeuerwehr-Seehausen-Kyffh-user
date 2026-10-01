import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/home_navigation.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _bg = Color(0xFF020B13);
  static const _panel = Color(0xFF071421);
  static const _panel2 = Color(0xFF0A1A29);
  static const _blue = Color(0xFF00A8FF);
  static const _red = Color(0xFFE30613);
  static const _muted = Color(0xFF9FB0C0);

  bool _loading = true;
  bool _isTrainer = false;
  String? _role;
  bool _eventRemindersEnabled = true;
  int _reminderMinutes = 30;
  String? _error;
  bool _usingOfflineCache = false;
  DateTime? _lastSyncedAt;

  List<Map<String, dynamic>> _events = [];
  final Map<String, String> _attendanceByEvent = {};
  String _searchQuery = '';
  String _timeFilter = 'kommend';
  String _typeFilter = 'alle';

  String _eventsKey(String userId) => 'events_cache_v1_${userId}_events';
  String _attendanceKey(String userId) =>
      'events_cache_v1_${userId}_attendance';
  String _syncedKey(String userId) =>
      'events_cache_v1_${userId}_synced_at';

  Future<void> _saveOfflineCache() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString(_eventsKey(user.id), jsonEncode(_events));
    await prefs.setString(
      _attendanceKey(user.id),
      jsonEncode(_attendanceByEvent),
    );
    await prefs.setString(_syncedKey(user.id), now.toIso8601String());
    _lastSyncedAt = now;
  }

  Future<bool> _loadOfflineCache() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final rawEvents = prefs.getString(_eventsKey(user.id));
    if (rawEvents == null) return false;

    try {
      final decoded = jsonDecode(rawEvents);
      if (decoded is! List) return false;
      _events = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final rawAttendance = prefs.getString(_attendanceKey(user.id));
      _attendanceByEvent.clear();
      if (rawAttendance != null) {
        final decodedAttendance = jsonDecode(rawAttendance);
        if (decodedAttendance is Map) {
          decodedAttendance.forEach((key, value) {
            _attendanceByEvent[key.toString()] = value.toString();
          });
        }
      }

      _lastSyncedAt =
          DateTime.tryParse(prefs.getString(_syncedKey(user.id)) ?? '');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadRole();
    await _loadEvents();
  }

  Future<void> _loadRole() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await _supabase
          .from('profiles')
          .select('id, role, event_reminders_enabled, reminder_minutes')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      final role = profile?['role']?.toString().trim().toLowerCase();
      setState(() {
        _role = role;
        _isTrainer = role == 'ausbilder';
        _eventRemindersEnabled = profile?['event_reminders_enabled'] != false;
        _reminderMinutes =
            (profile?['reminder_minutes'] as num?)?.toInt() ?? 30;
      });
    } catch (error) {
      debugPrint('Fehler beim Laden der Rolle: $error');
      if (!mounted) return;
      setState(() => _isTrainer = false);
    }
  }

  Future<void> _loadEvents() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final response =
          await _supabase.from('events').select().order('starts_at');

      final attendance = <String, String>{};
      final user = _supabase.auth.currentUser;

      if (user != null) {
        final rows = await _supabase
            .from('event_attendance')
            .select('event_id,status')
            .eq('user_id', user.id);

        for (final row in rows) {
          final eventId = row['event_id']?.toString();
          final status = row['status']?.toString();
          if (eventId != null && status != null) {
            attendance[eventId] = status;
          }
        }
      }

      _events = List<Map<String, dynamic>>.from(response);
      _attendanceByEvent
        ..clear()
        ..addAll(attendance);
      await _saveOfflineCache();

      if (!mounted) return;
      setState(() {
        _usingOfflineCache = false;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      final hasCache = await _loadOfflineCache();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _usingOfflineCache = hasCache;
        _error = hasCache ? null : error.toString();
      });
    }
  }

  String _reminderLabel() {
    if (!_eventRemindersEnabled) return 'Ausgeschaltet';
    switch (_reminderMinutes) {
      case 15:
        return '15 Min. vorher';
      case 30:
        return '30 Min. vorher';
      case 60:
        return '1 Std. vorher';
      case 120:
        return '2 Std. vorher';
      case 180:
        return '3 Std. vorher';
      case 1440:
        return '1 Tag vorher';
      default:
        if (_reminderMinutes % 60 == 0) {
          return '${_reminderMinutes ~/ 60} Std. vorher';
        }
        return '$_reminderMinutes Min. vorher';
    }
  }

  String _attendanceLabel(String? status) {
    switch (status) {
      case 'zugesagt':
        return 'Ich nehme teil';
      case 'abgesagt':
        return 'Ich nehme nicht teil';
      case 'entschuldigt':
        return 'Entschuldigt';
      default:
        return 'Noch offen';
    }
  }

  Color _attendanceColor(String? status) {
    switch (status) {
      case 'zugesagt':
        return const Color(0xFF22C55E);
      case 'abgesagt':
        return const Color(0xFFFF3948);
      case 'entschuldigt':
        return const Color(0xFFFFA629);
      default:
        return const Color(0xFF8A95A5);
    }
  }

  IconData _attendanceIcon(String? status) {
    switch (status) {
      case 'zugesagt':
        return Icons.check_circle_rounded;
      case 'abgesagt':
        return Icons.cancel_rounded;
      case 'entschuldigt':
        return Icons.info_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  Future<void> _setAttendance(
    Map<String, dynamic> event,
    String status,
  ) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('event_attendance').upsert(
        {
          'event_id': event['id'],
          'user_id': user.id,
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'event_id,user_id',
      );

      if (!mounted) return;
      setState(() {
        _attendanceByEvent[event['id'].toString()] = status;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Teilnahme gespeichert: ${_attendanceLabel(status)}'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Teilnahme konnte nicht gespeichert werden: $error'),
        ),
      );
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _date(DateTime? date) {
    if (date == null) return '-';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year}';
  }

  String _time(DateTime? date) {
    if (date == null) return '--:--';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)}';
  }

  String _monthShort(DateTime? date) {
    if (date == null) return '';
    const months = [
      'JAN', 'FEB', 'MÄR', 'APR', 'MAI', 'JUN',
      'JUL', 'AUG', 'SEP', 'OKT', 'NOV', 'DEZ',
    ];
    return months[date.month - 1];
  }

  String _weekday(DateTime? date) {
    if (date == null) return '';
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return days[date.weekday - 1];
  }

  String _typeName(String type) {
    switch (type) {
      case 'dienst':
        return 'Dienst';
      case 'veranstaltung':
        return 'Veranstaltung';
      case 'wettbewerb':
        return 'Wettbewerb';
      case 'zeltlager':
        return 'Zeltlager';
      case 'elternabend':
        return 'Elternabend';
      case 'sonstiges':
        return 'Sonstiges';
      default:
        return 'Termin';
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'dienst':
        return Icons.local_fire_department_rounded;
      case 'veranstaltung':
        return Icons.celebration_rounded;
      case 'wettbewerb':
        return Icons.emoji_events_rounded;
      case 'zeltlager':
        return Icons.cabin_rounded;
      case 'elternabend':
        return Icons.family_restroom_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  bool _isPastEvent(Map<String, dynamic> event) {
    final end = _parseDate(event['ends_at']);
    final start = _parseDate(event['starts_at']);
    final reference = end ?? start;
    if (reference == null) return false;
    return reference.isBefore(DateTime.now());
  }

  List<Map<String, dynamic>> get _filteredEvents {
    final query = _searchQuery.trim().toLowerCase();
    final result = _events.where((event) {
      final title = event['title']?.toString().toLowerCase() ?? '';
      final location = event['location']?.toString().toLowerCase() ?? '';
      final description = event['description']?.toString().toLowerCase() ?? '';
      final type = event['event_type']?.toString() ?? 'dienst';
      final isPast = _isPastEvent(event);

      final matchesSearch = query.isEmpty ||
          title.contains(query) ||
          location.contains(query) ||
          description.contains(query);

      final matchesTime = _timeFilter == 'alle' ||
          (_timeFilter == 'kommend' && !isPast) ||
          (_timeFilter == 'vergangen' && isPast);

      final matchesType = _typeFilter == 'alle' || _typeFilter == type;
      return matchesSearch && matchesTime && matchesType;
    }).map((e) => Map<String, dynamic>.from(e)).toList();

    result.sort((a, b) {
      final aDate = _parseDate(a['starts_at']);
      final bDate = _parseDate(b['starts_at']);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      if (_timeFilter == 'vergangen') return bDate.compareTo(aDate);
      return aDate.compareTo(bDate);
    });

    return result;
  }

  int _timeCount(String filter) {
    if (filter == 'alle') return _events.length;
    if (filter == 'vergangen') return _events.where(_isPastEvent).length;
    return _events.where((event) => !_isPastEvent(event)).length;
  }

  int _typeCount(String type) {
    if (type == 'alle') return _events.length;
    return _events
        .where((event) => event['event_type']?.toString() == type)
        .length;
  }

  Future<void> _openEditor({Map<String, dynamic>? event}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventEditor(event: event),
    );
    if (changed == true) await _loadEvents();
  }

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
    final title = event['title']?.toString() ?? 'Termin';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: const Text(
          'Termin löschen?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Soll "$title" wirklich gelöscht werden?',
          style: const TextStyle(color: Color(0xFFD6E0EA)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase.from('events').delete().eq('id', event['id']);

      try {
        await _supabase.functions.invoke(
          'send-push',
          body: {
            'title': 'Termin abgesagt',
            'body': '$title wurde gelöscht.',
          },
        );
      } catch (pushError) {
        debugPrint('Termin gelöscht, Push fehlgeschlagen: $pushError');
      }

      await _loadEvents();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Termin wurde gelöscht.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $error')),
      );
    }
  }

  Future<void> _showAttendanceOverview(
    Map<String, dynamic> event,
  ) async {
    try {
      final profiles = await _supabase
          .from('profiles')
          .select('id,first_name,last_name,role')
          .eq('role', 'jugendmitglied')
          .order('last_name')
          .order('first_name');

      final attendanceRows = await _supabase
          .from('event_attendance')
          .select('status,user_id')
          .eq('event_id', event['id']);

      final byUser = <String, String>{};
      for (final row in attendanceRows) {
        final userId = row['user_id']?.toString();
        final status = row['status']?.toString();
        if (userId != null && status != null) byUser[userId] = status;
      }

      final data = <Map<String, dynamic>>[];
      for (final raw in profiles) {
        final profile = Map<String, dynamic>.from(raw);
        final userId = profile['id']?.toString() ?? '';
        data.add({
          'user_id': userId,
          'status': byUser[userId] ?? 'offen',
          'profiles': profile,
        });
      }

      int countFor(String status) =>
          data.where((row) => row['status']?.toString() == status).length;
      final answered =
          data.where((row) => row['status']?.toString() != 'offen').length;

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final grouped = <String, List<Map<String, dynamic>>>{
            'zugesagt': [],
            'abgesagt': [],
            'entschuldigt': [],
            'offen': [],
          };
          for (final row in data) {
            final status = row['status']?.toString() ?? 'offen';
            grouped.putIfAbsent(status, () => []);
            grouped[status]!.add(row);
          }

          Widget section(
            String title,
            String status,
            IconData icon,
            Color color,
          ) {
            final entries = grouped[status] ?? const <Map<String, dynamic>>[];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: _panel2,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withValues(alpha: 0.32)),
              ),
              child: ExpansionTile(
                iconColor: color,
                collapsedIconColor: _muted,
                leading: Icon(icon, color: color),
                title: Text(
                  '$title (${entries.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                children: entries.isEmpty
                    ? const [
                        ListTile(
                          title: Text(
                            'Keine Einträge',
                            style: TextStyle(color: _muted),
                          ),
                        ),
                      ]
                    : entries.map((row) {
                        final profile =
                            row['profiles'] as Map<String, dynamic>?;
                        final first =
                            profile?['first_name']?.toString().trim() ?? '';
                        final last =
                            profile?['last_name']?.toString().trim() ?? '';
                        final name = '$first $last'.trim();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.14),
                            child: Icon(Icons.person_rounded, color: color),
                          ),
                          title: Text(
                            name.isEmpty ? 'Jugendmitglied' : name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            status == 'offen'
                                ? 'Noch keine Rückmeldung'
                                : _attendanceLabel(status),
                            style: const TextStyle(color: _muted),
                          ),
                        );
                      }).toList(),
              ),
            );
          }

          return _DarkSheet(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _SheetHandle(),
                const SizedBox(height: 16),
                Text(
                  event['title']?.toString() ?? 'Teilnehmerübersicht',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$answered von ${data.length} Jugendmitgliedern haben geantwortet',
                  style: const TextStyle(color: _muted),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: data.isEmpty ? 0 : answered / data.length,
                    minHeight: 8,
                    backgroundColor: const Color(0xFF102437),
                    color: _blue,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.check_circle_rounded,
                        label: 'Zugesagt',
                        value: countFor('zugesagt'),
                        color: const Color(0xFF22C55E),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.cancel_rounded,
                        label: 'Abgesagt',
                        value: countFor('abgesagt'),
                        color: const Color(0xFFFF3948),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.help_rounded,
                        label: 'Offen',
                        value: countFor('offen'),
                        color: const Color(0xFF8A95A5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.info_rounded,
                        label: 'Entschuldigt',
                        value: countFor('entschuldigt'),
                        color: const Color(0xFFFFA629),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                section(
                  'Zugesagt',
                  'zugesagt',
                  Icons.check_circle_rounded,
                  const Color(0xFF22C55E),
                ),
                section(
                  'Abgesagt',
                  'abgesagt',
                  Icons.cancel_rounded,
                  const Color(0xFFFF3948),
                ),
                section(
                  'Noch offen',
                  'offen',
                  Icons.help_rounded,
                  const Color(0xFF8A95A5),
                ),
                section(
                  'Entschuldigt',
                  'entschuldigt',
                  Icons.info_rounded,
                  const Color(0xFFFFA629),
                ),
              ],
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Teilnehmerübersicht konnte nicht geladen werden: $error',
          ),
        ),
      );
    }
  }

  void _showDetails(Map<String, dynamic> event) {
    final start = _parseDate(event['starts_at']);
    final end = _parseDate(event['ends_at']);
    final eventId = event['id']?.toString();
    final attendance = _attendanceByEvent[eventId];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _DarkSheet(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _blue.withValues(alpha: 0.38),
                        ),
                      ),
                      child: Icon(
                        _typeIcon(
                          event['event_type']?.toString() ?? 'dienst',
                        ),
                        color: _blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event['title']?.toString() ?? 'Termin',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _typeName(
                              event['event_type']?.toString() ?? 'dienst',
                            ),
                            style: const TextStyle(
                              color: _blue,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _DetailRow(
                  icon: Icons.calendar_today_rounded,
                  title: 'Datum',
                  value: _date(start),
                ),
                _DetailRow(
                  icon: Icons.schedule_rounded,
                  title: 'Uhrzeit',
                  value: end == null
                      ? '${_time(start)} Uhr'
                      : '${_time(start)} – ${_time(end)} Uhr',
                ),
                _DetailRow(
                  icon: _eventRemindersEnabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  title: 'Erinnerung',
                  value: _reminderLabel(),
                ),
                if ((event['location'] ?? '').toString().isNotEmpty)
                  _DetailRow(
                    icon: Icons.location_on_rounded,
                    title: 'Ort',
                    value: event['location'].toString(),
                  ),
                if ((event['meeting_point'] ?? '').toString().isNotEmpty)
                  _DetailRow(
                    icon: Icons.groups_rounded,
                    title: 'Treffpunkt',
                    value: event['meeting_point'].toString(),
                  ),
                if ((event['required_equipment'] ?? '').toString().isNotEmpty)
                  _DetailRow(
                    icon: Icons.backpack_rounded,
                    title: 'Ausrüstung',
                    value: event['required_equipment'].toString(),
                  ),
                if ((event['description'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Beschreibung',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    event['description'].toString(),
                    style: const TextStyle(
                      color: Color(0xFFD6E0EA),
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (_role != 'eltern') ...[
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: _attendanceColor(attendance)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _attendanceColor(attendance)
                            .withValues(alpha: 0.34),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _attendanceIcon(attendance),
                          color: _attendanceColor(attendance),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Deine Rückmeldung: ${_attendanceLabel(attendance)}',
                            style: TextStyle(
                              color: _attendanceColor(attendance),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Rückmeldung ändern',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AttendanceChoice(
                        label: 'Teilnehmen',
                        icon: Icons.check_rounded,
                        color: const Color(0xFF22C55E),
                        selected: attendance == 'zugesagt',
                        onTap: () {
                          Navigator.pop(context);
                          _setAttendance(event, 'zugesagt');
                        },
                      ),
                      _AttendanceChoice(
                        label: 'Absagen',
                        icon: Icons.close_rounded,
                        color: const Color(0xFFFF3948),
                        selected: attendance == 'abgesagt',
                        onTap: () {
                          Navigator.pop(context);
                          _setAttendance(event, 'abgesagt');
                        },
                      ),
                      _AttendanceChoice(
                        label: 'Entschuldigt',
                        icon: Icons.info_outline_rounded,
                        color: const Color(0xFFFFA629),
                        selected: attendance == 'entschuldigt',
                        onTap: () {
                          Navigator.pop(context);
                          _setAttendance(event, 'entschuldigt');
                        },
                      ),
                    ],
                  ),
                ] else
                  const Text(
                    'Eltern können den Termin einsehen. Die Rückmeldung erfolgt über das Jugendmitglied.',
                    style: TextStyle(color: _muted, height: 1.4),
                  ),
                if (_isTrainer) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showAttendanceOverview(event);
                      },
                      icon: const Icon(Icons.groups_rounded),
                      label: const Text('Teilnehmerübersicht'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _blue),
                      onPressed: () {
                        Navigator.pop(context);
                        _openEditor(event: event);
                      },
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Termin bearbeiten'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF7580),
                        side: const BorderSide(color: Color(0xFF7B2830)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteEvent(event);
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Termin löschen'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      backgroundColor: _panel2,
      selectedColor: _blue.withValues(alpha: 0.18),
      side: BorderSide(
        color: selected
            ? _blue.withValues(alpha: 0.78)
            : const Color(0xFF1C3448),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : _muted,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ColoredBox(
        color: _bg,
        child: Center(
          child: CircularProgressIndicator(color: _blue),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: _red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Termine konnten nicht geladen werden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _blue),
                    onPressed: _loadEvents,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Erneut versuchen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final filtered = _filteredEvents;

    return Scaffold(
      backgroundColor: _bg,
      body: RefreshIndicator(
        color: _blue,
        backgroundColor: _panel,
        onRefresh: _loadEvents,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration: BoxDecoration(
                color: _panel,
                border: Border(
                  bottom: BorderSide(
                    color: _blue.withValues(alpha: 0.28),
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Zur Startseite',
                        onPressed: () => HomeNavigation.goHome(context),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF0C2133),
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: _blue.withValues(alpha: 0.28),
                          ),
                        ),
                        icon: const Icon(Icons.home_rounded),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 46,
                        height: 46,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF051420),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _blue.withValues(alpha: 0.46),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.asset(
                            'assets/branding/logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Termine',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Dienstplan & Veranstaltungen',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isTrainer)
                        IconButton(
                          tooltip: 'Termin erstellen',
                          onPressed: () => _openEditor(),
                          style: IconButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.add_rounded),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _usingOfflineCache
                          ? const Color(0xFF5B3A00)
                          : const Color(0xFF123B2A),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _usingOfflineCache
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_done_outlined,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _usingOfflineCache
                                ? 'Offline – gespeicherte Termine'
                                  '${_lastSyncedAt == null ? '' : ' vom ${_date(_lastSyncedAt)}'}.'
                                : 'Online – Termine synchronisiert'
                                  '${_lastSyncedAt == null ? '' : ' am ${_date(_lastSyncedAt)}'}.',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Synchronisieren',
                          onPressed: _loading ? null : _loadEvents,
                          color: Colors.white,
                          icon: const Icon(Icons.sync_outlined),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) =>
                        setState(() => _searchQuery = value),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Termin, Ort oder Beschreibung suchen',
                      hintStyle: const TextStyle(color: Color(0xFF718497)),
                      prefixIcon:
                          const Icon(Icons.search_rounded, color: _muted),
                      filled: true,
                      fillColor: _panel,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _blue.withValues(alpha: 0.24),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _blue.withValues(alpha: 0.24),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: _blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _filterChip(
                          label: 'Kommend (${_timeCount('kommend')})',
                          selected: _timeFilter == 'kommend',
                          onTap: () =>
                              setState(() => _timeFilter = 'kommend'),
                        ),
                        const SizedBox(width: 8),
                        _filterChip(
                          label: 'Vergangen (${_timeCount('vergangen')})',
                          selected: _timeFilter == 'vergangen',
                          onTap: () =>
                              setState(() => _timeFilter = 'vergangen'),
                        ),
                        const SizedBox(width: 8),
                        _filterChip(
                          label: 'Alle (${_timeCount('alle')})',
                          selected: _timeFilter == 'alle',
                          onTap: () => setState(() => _timeFilter = 'alle'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final type in const [
                          'alle',
                          'dienst',
                          'veranstaltung',
                          'wettbewerb',
                          'zeltlager',
                          'elternabend',
                          'sonstiges',
                        ]) ...[
                          _filterChip(
                            label:
                                '${type == 'alle' ? 'Alle Arten' : _typeName(type)} (${_typeCount(type)})',
                            selected: _typeFilter == type,
                            onTap: () => setState(() => _typeFilter = type),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 100),
              child: _events.isEmpty
                  ? const _EmptyState(
                      icon: Icons.calendar_month_outlined,
                      title: 'Noch keine Termine vorhanden.',
                    )
                  : filtered.isEmpty
                      ? const _EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'Keine passenden Termine gefunden.',
                        )
                      : Column(
                          children: filtered.map((event) {
                            final start = _parseDate(event['starts_at']);
                            final end = _parseDate(event['ends_at']);
                            final type =
                                event['event_type']?.toString() ?? 'dienst';
                            final status =
                                _attendanceByEvent[event['id']?.toString()];
                            final statusColor = _attendanceColor(status);
                            final isPast = _isPastEvent(event);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: _panel,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: isPast
                                      ? const Color(0xFF1C3448)
                                      : _blue.withValues(alpha: 0.34),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _blue.withValues(
                                      alpha: isPast ? 0.02 : 0.05,
                                    ),
                                    blurRadius: 18,
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _showDetails(event),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 68,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                _blue.withValues(alpha: 0.17),
                                                const Color(0xFF091B2A),
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            border: Border.all(
                                              color:
                                                  _blue.withValues(alpha: 0.28),
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                _weekday(start),
                                                style: const TextStyle(
                                                  color: _muted,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                start == null
                                                    ? '--'
                                                    : start.day
                                                        .toString()
                                                        .padLeft(2, '0'),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w900,
                                                  height: 1,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _monthShort(start),
                                                style: const TextStyle(
                                                  color: _blue,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 13),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: _blue.withValues(
                                                        alpha: 0.10,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        999,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          _typeIcon(type),
                                                          color: _blue,
                                                          size: 13,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          _typeName(type),
                                                          style:
                                                              const TextStyle(
                                                            color: _blue,
                                                            fontSize: 10.5,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  if (isPast)
                                                    const Text(
                                                      'VERGANGEN',
                                                      style: TextStyle(
                                                        color:
                                                            Color(0xFF7F91A3),
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        letterSpacing: 0.6,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 7),
                                              Text(
                                                event['title']?.toString() ??
                                                    'Termin',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w900,
                                                  height: 1.15,
                                                ),
                                              ),
                                              const SizedBox(height: 9),
                                              _TinyInfo(
                                                icon: Icons.schedule_rounded,
                                                text: end == null
                                                    ? '${_time(start)} Uhr'
                                                    : '${_time(start)} – ${_time(end)} Uhr',
                                              ),
                                              if ((event['location'] ?? '')
                                                  .toString()
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 5),
                                                _TinyInfo(
                                                  icon:
                                                      Icons.location_on_rounded,
                                                  text: event['location']
                                                      .toString(),
                                                ),
                                              ],
                                              if (_role != 'eltern') ...[
                                                const SizedBox(height: 9),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 9,
                                                    vertical: 6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: statusColor
                                                        .withValues(alpha: 0.10),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      10,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        _attendanceIcon(status),
                                                        size: 15,
                                                        color: statusColor,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Flexible(
                                                        child: Text(
                                                          _attendanceLabel(
                                                            status,
                                                          ),
                                                          style: TextStyle(
                                                            color: statusColor,
                                                            fontSize: 11.5,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        const Padding(
                                          padding: EdgeInsets.only(top: 36),
                                          child: Icon(
                                            Icons.chevron_right_rounded,
                                            color: Color(0xFF718497),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isTrainer
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              backgroundColor: _red,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Termin',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
    );
  }
}

class EventEditor extends StatefulWidget {
  final Map<String, dynamic>? event;

  const EventEditor({
    super.key,
    this.event,
  });

  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _panel = Color(0xFF071421);
  static const _panel2 = Color(0xFF0A1A29);
  static const _blue = Color(0xFF00A8FF);
  static const _muted = Color(0xFF9FB0C0);

  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _meetingPoint;
  late final TextEditingController _equipment;

  String _type = 'dienst';
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  DateTime? _end;
  bool _saving = false;

  bool get _editing => widget.event != null;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _title = TextEditingController(text: event?['title']?.toString() ?? '');
    _description =
        TextEditingController(text: event?['description']?.toString() ?? '');
    _location =
        TextEditingController(text: event?['location']?.toString() ?? '');
    _meetingPoint =
        TextEditingController(text: event?['meeting_point']?.toString() ?? '');
    _equipment = TextEditingController(
      text: event?['required_equipment']?.toString() ?? '',
    );

    if (event != null) {
      _type = event['event_type']?.toString() ?? 'dienst';
      _start =
          DateTime.tryParse(event['starts_at']?.toString() ?? '')?.toLocal() ??
              _start;
      _end =
          DateTime.tryParse(event['ends_at']?.toString() ?? '')?.toLocal();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _meetingPoint.dispose();
    _equipment.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Future<DateTime?> _selectDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;

    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Titel eingeben.')),
      );
      return;
    }

    if (_end != null && _end!.isBefore(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Endzeit darf nicht vor der Startzeit liegen.'),
        ),
      );
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    final data = {
      'title': _title.text.trim(),
      'description':
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      'event_type': _type,
      'starts_at': _start.toUtc().toIso8601String(),
      'ends_at': _end?.toUtc().toIso8601String(),
      'location':
          _location.text.trim().isEmpty ? null : _location.text.trim(),
      'meeting_point':
          _meetingPoint.text.trim().isEmpty ? null : _meetingPoint.text.trim(),
      'required_equipment':
          _equipment.text.trim().isEmpty ? null : _equipment.text.trim(),
    };

    try {
      if (_editing) {
        await _supabase
            .from('events')
            .update(data)
            .eq('id', widget.event!['id']);
      } else {
        await _supabase.from('events').insert({
          ...data,
          'created_by': user.id,
        });
      }

      try {
        final startLocal = _start.toLocal();
        final dateText =
            '${startLocal.day.toString().padLeft(2, '0')}.'
            '${startLocal.month.toString().padLeft(2, '0')}.'
            '${startLocal.year} um '
            '${startLocal.hour.toString().padLeft(2, '0')}:'
            '${startLocal.minute.toString().padLeft(2, '0')} Uhr';

        await _supabase.functions.invoke(
          'send-push',
          body: {
            'title': _editing ? 'Termin geändert' : 'Neuer Termin',
            'body': '${_title.text.trim()} – $dateText',
          },
        );
      } catch (pushError) {
        debugPrint('Termin gespeichert, Push fehlgeschlagen: $pushError');
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
      );
    }
  }

  InputDecoration _decoration(
    String label,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted),
      prefixIcon: Icon(icon, color: _blue),
      filled: true,
      fillColor: _panel2,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF1C3448)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _blue),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _DarkSheet(
      child: Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(
            primary: _blue,
            surface: _panel,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 16),
              Text(
                _editing ? 'Termin bearbeiten' : 'Neuen Termin erstellen',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Alle wichtigen Angaben übersichtlich eintragen.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _title,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration(
                  'Titel',
                  Icons.title_rounded,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                dropdownColor: _panel2,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration(
                  'Art des Termins',
                  Icons.category_rounded,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'dienst',
                    child: Text('Dienst'),
                  ),
                  DropdownMenuItem(
                    value: 'veranstaltung',
                    child: Text('Veranstaltung'),
                  ),
                  DropdownMenuItem(
                    value: 'wettbewerb',
                    child: Text('Wettbewerb'),
                  ),
                  DropdownMenuItem(
                    value: 'zeltlager',
                    child: Text('Zeltlager'),
                  ),
                  DropdownMenuItem(
                    value: 'elternabend',
                    child: Text('Elternabend'),
                  ),
                  DropdownMenuItem(
                    value: 'sonstiges',
                    child: Text('Sonstiges'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              const SizedBox(height: 12),
              _EditorDateTile(
                icon: Icons.event_rounded,
                title: 'Beginn',
                value: _formatDateTime(_start),
                onTap: () async {
                  final selected = await _selectDateTime(_start);
                  if (selected != null) setState(() => _start = selected);
                },
              ),
              const SizedBox(height: 10),
              _EditorDateTile(
                icon: Icons.event_available_rounded,
                title: 'Ende',
                value:
                    _end == null ? 'Nicht angegeben' : _formatDateTime(_end!),
                onTap: () async {
                  final selected = await _selectDateTime(
                    _end ?? _start.add(const Duration(hours: 2)),
                  );
                  if (selected != null) setState(() => _end = selected);
                },
                onClear: _end == null ? null : () => setState(() => _end = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _location,
                style: const TextStyle(color: Colors.white),
                decoration:
                    _decoration('Ort', Icons.location_on_rounded),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _meetingPoint,
                style: const TextStyle(color: Colors.white),
                decoration:
                    _decoration('Treffpunkt', Icons.groups_rounded),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _equipment,
                style: const TextStyle(color: Colors.white),
                decoration:
                    _decoration('Benötigte Ausrüstung', Icons.backpack_rounded),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration:
                    _decoration('Beschreibung', Icons.notes_rounded),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _blue),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _editing ? 'Änderungen speichern' : 'Termin erstellen',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DarkSheet extends StatelessWidget {
  final Widget child;

  const _DarkSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF071421),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: child,
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFF31485B),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _TinyInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TinyInfo({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: const Color(0xFF8FA2B4),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFC1CEDA),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;

  const _EmptyState({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 46),
      decoration: BoxDecoration(
        color: const Color(0xFF071421),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1C3448)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 58,
            color: const Color(0xFF00A8FF),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AttendanceChoice({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? color.withValues(alpha: 0.18)
          : const Color(0xFF0A1A29),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.75)
                  : const Color(0xFF1C3448),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorDateTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _EditorDateTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0A1A29),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1C3448)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 2),
              Icon(icon, color: const Color(0xFF00A8FF)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF9FB0C0),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: 'Ende entfernen',
                  onPressed: onClear,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF9FB0C0),
                  ),
                )
              else
                const Icon(
                  Icons.edit_calendar_rounded,
                  color: Color(0xFF9FB0C0),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 5),
          Text(
            value.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9FB0C0),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A29),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF1C3448)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF00A8FF).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF00A8FF),
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF9FB0C0),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
