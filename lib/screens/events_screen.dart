import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  String? _role;
  String? _error;

  List<Map<String, dynamic>> _events = [];
  final Map<String, String> _attendanceByEvent = {};

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

    if (user == null) {
      debugPrint('Kein Benutzer angemeldet');
      return;
    }

    try {
      final profile = await _supabase
          .from('profiles')
          .select('id, role')
          .eq('id', user.id)
          .maybeSingle();

      debugPrint('User-ID: ${user.id}');
      debugPrint('Profil: $profile');

      if (!mounted) return;

      final role = profile?['role']?.toString().trim().toLowerCase();

      setState(() {
        _role = role;
        _isTrainer = role == 'ausbilder';
      });

      debugPrint('Rolle: $role');
      debugPrint('Ist Ausbilder: $_isTrainer');
    } catch (error) {
      debugPrint('Fehler beim Laden der Rolle: $error');

      if (!mounted) return;

      setState(() {
        _isTrainer = false;
      });
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
      final response = await _supabase
          .from('events')
          .select()
          .order('starts_at', ascending: true);

      final attendance = <String, String>{};
      final user = _supabase.auth.currentUser;

      if (user != null) {
        final attendanceRows = await _supabase
            .from('event_attendance')
            .select('event_id,status')
            .eq('user_id', user.id);

        for (final row in attendanceRows) {
          final eventId = row['event_id']?.toString();
          final status = row['status']?.toString();

          if (eventId != null && status != null) {
            attendance[eventId] = status;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _events = List<Map<String, dynamic>>.from(response);
        _attendanceByEvent
          ..clear()
          ..addAll(attendance);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString();
      });
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
      case 'offen':
      default:
        return 'Noch offen';
    }
  }

  Future<void> _setAttendance(
    Map<String, dynamic> event,
    String status,
  ) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return;
    }

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

    return DateTime.tryParse(
      value.toString(),
    )?.toLocal();
  }

  String _date(DateTime? date) {
    if (date == null) return '-';

    String two(int value) {
      return value.toString().padLeft(2, '0');
    }

    return '${two(date.day)}.${two(date.month)}.${date.year}';
  }

  String _time(DateTime? date) {
    if (date == null) return '--:--';

    String two(int value) {
      return value.toString().padLeft(2, '0');
    }

    return '${two(date.hour)}:${two(date.minute)}';
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

  String _monthShort(DateTime? date) {
    if (date == null) return '';
    const months = [
      'JAN',
      'FEB',
      'MÄR',
      'APR',
      'MAI',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OKT',
      'NOV',
      'DEZ',
    ];
    return months[date.month - 1];
  }

  Color _attendanceColor(String? status) {
    switch (status) {
      case 'zugesagt':
        return const Color(0xFF16A34A);
      case 'abgesagt':
        return const Color(0xFFE30613);
      case 'entschuldigt':
        return const Color(0xFFFF8A00);
      default:
        return const Color(0xFF8A95A5);
    }
  }

  Future<void> _openEditor({
    Map<String, dynamic>? event,
  }) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) {
        return EventEditor(
          event: event,
        );
      },
    );

    if (changed == true) {
      await _loadEvents();
    }
  }

  Future<void> _deleteEvent(
    Map<String, dynamic> event,
  ) async {
    final title = event['title']?.toString() ?? 'Termin';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Termin löschen?',
          ),
          content: Text(
            'Soll "$title" wirklich gelöscht werden?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'Abbrechen',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text(
                'Löschen',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _supabase.from('events').delete().eq(
            'id',
            event['id'],
          );

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
        const SnackBar(
          content: Text(
            'Termin wurde gelöscht.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Löschen fehlgeschlagen: $error',
          ),
        ),
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

      final attendanceByUser = <String, String>{};
      for (final row in attendanceRows) {
        final userId = row['user_id']?.toString();
        final status = row['status']?.toString();
        if (userId != null && status != null) {
          attendanceByUser[userId] = status;
        }
      }

      final data = <Map<String, dynamic>>[];
      for (final profileRaw in profiles) {
        final profile = Map<String, dynamic>.from(profileRaw);
        final userId = profile['id']?.toString() ?? '';
        data.add({
          'user_id': userId,
          'status': attendanceByUser[userId] ?? 'offen',
          'profiles': profile,
        });
      }

      int countFor(String status) {
        return data.where((row) => row['status']?.toString() == status).length;
      }

      final answered =
          data.where((row) => row['status']?.toString() != 'offen').length;

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
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

          for (final entries in grouped.values) {
            entries.sort((a, b) {
              final pa = a['profiles'] as Map<String, dynamic>?;
              final pb = b['profiles'] as Map<String, dynamic>?;
              final aName =
                  '${pa?['last_name'] ?? ''} ${pa?['first_name'] ?? ''}'
                      .trim()
                      .toLowerCase();
              final bName =
                  '${pb?['last_name'] ?? ''} ${pb?['first_name'] ?? ''}'
                      .trim()
                      .toLowerCase();
              return aName.compareTo(bName);
            });
          }

          Widget section(
            String title,
            String status,
            IconData icon,
            Color color,
          ) {
            final entries = grouped[status] ?? const <Map<String, dynamic>>[];

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                initiallyExpanded: status == 'offen' && entries.isNotEmpty,
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icon, color: color),
                ),
                title: Text(
                  '$title (${entries.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                children: entries.isEmpty
                    ? const [
                        ListTile(
                          title: Text('Keine Einträge'),
                        ),
                      ]
                    : entries.map((row) {
                        final profile =
                            row['profiles'] as Map<String, dynamic>?;

                        final firstName =
                            profile?['first_name']?.toString().trim() ?? '';
                        final lastName =
                            profile?['last_name']?.toString().trim() ?? '';

                        final name = '$firstName $lastName'.trim();
                        final displayName =
                            name.isEmpty ? 'Jugendmitglied' : name;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Icon(Icons.person, color: color),
                          ),
                          title: Text(displayName),
                          subtitle: Text(
                            status == 'offen'
                                ? 'Noch keine Rückmeldung'
                                : _attendanceLabel(status),
                          ),
                        );
                      }).toList(),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event['title']?.toString() ?? 'Teilnehmerübersicht',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$answered von ${data.length} Jugendmitgliedern haben geantwortet',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: data.isEmpty ? 0 : answered / data.length,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(999),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.check_circle,
                        label: 'Zugesagt',
                        value: countFor('zugesagt'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.cancel,
                        label: 'Abgesagt',
                        value: countFor('abgesagt'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.help_outline,
                        label: 'Offen',
                        value: countFor('offen'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.info,
                        label: 'Entschuldigt',
                        value: countFor('entschuldigt'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                section(
                  'Zugesagt',
                  'zugesagt',
                  Icons.check_circle,
                  const Color(0xFF16A34A),
                ),
                section(
                  'Abgesagt',
                  'abgesagt',
                  Icons.cancel,
                  const Color(0xFFE30613),
                ),
                section(
                  'Noch offen',
                  'offen',
                  Icons.help_outline,
                  const Color(0xFF8A95A5),
                ),
                section(
                  'Entschuldigt',
                  'entschuldigt',
                  Icons.info,
                  const Color(0xFFFF8A00),
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

  void _showDetails(
    Map<String, dynamic> event,
  ) {
    final start = _parseDate(
      event['starts_at'],
    );

    final end = _parseDate(
      event['ends_at'],
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event['title']?.toString() ?? 'Termin',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _typeName(
                  event['event_type']?.toString() ?? 'dienst',
                ),
                style: const TextStyle(
                  color: Color(0xFFE30613),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              _DetailRow(
                icon: Icons.calendar_today,
                title: 'Datum',
                value: _date(start),
              ),
              _DetailRow(
                icon: Icons.access_time,
                title: 'Uhrzeit',
                value: end == null
                    ? _time(start)
                    : '${_time(start)} - ${_time(end)}',
              ),
              if ((event['location'] ?? '').toString().isNotEmpty)
                _DetailRow(
                  icon: Icons.location_on,
                  title: 'Ort',
                  value: event['location'].toString(),
                ),
              if ((event['meeting_point'] ?? '').toString().isNotEmpty)
                _DetailRow(
                  icon: Icons.groups,
                  title: 'Treffpunkt',
                  value: event['meeting_point'].toString(),
                ),
              if ((event['required_equipment'] ?? '').toString().isNotEmpty)
                _DetailRow(
                  icon: Icons.backpack,
                  title: 'Ausrüstung',
                  value: event['required_equipment'].toString(),
                ),
              if ((event['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Beschreibung',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  event['description'].toString(),
                ),
              ],
              if (_role != 'eltern') ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'Teilnahme',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Aktueller Status: ${_attendanceLabel(_attendanceByEvent[event['id']?.toString()])}',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      avatar: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Ich nehme teil'),
                      selected: _attendanceByEvent[event['id']?.toString()] ==
                          'zugesagt',
                      onSelected: (_) {
                        _setAttendance(event, 'zugesagt');
                        Navigator.pop(context);
                      },
                    ),
                    ChoiceChip(
                      avatar: const Icon(Icons.cancel, size: 18),
                      label: const Text('Ich nehme nicht teil'),
                      selected: _attendanceByEvent[event['id']?.toString()] ==
                          'abgesagt',
                      onSelected: (_) {
                        _setAttendance(event, 'abgesagt');
                        Navigator.pop(context);
                      },
                    ),
                    ChoiceChip(
                      avatar: const Icon(Icons.info_outline, size: 18),
                      label: const Text('Entschuldigt'),
                      selected: _attendanceByEvent[event['id']?.toString()] ==
                          'entschuldigt',
                      onSelected: (_) {
                        _setAttendance(event, 'entschuldigt');
                        Navigator.pop(context);
                      },
                    ),
                    ChoiceChip(
                      avatar: const Icon(Icons.help_outline, size: 18),
                      label: const Text('Noch offen'),
                      selected: _attendanceByEvent[event['id']?.toString()] ==
                          'offen',
                      onSelected: (_) {
                        _setAttendance(event, 'offen');
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'Teilnahme',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Eltern können den Termin einsehen. Die Rückmeldung erfolgt über das Jugendmitglied.',
                ),
              ],
              if (_isTrainer) ...[
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAttendanceOverview(event);
                    },
                    icon: const Icon(
                      Icons.groups,
                    ),
                    label: const Text(
                      'Teilnehmerübersicht',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);

                      _openEditor(
                        event: event,
                      );
                    },
                    icon: const Icon(
                      Icons.edit,
                    ),
                    label: const Text(
                      'Termin bearbeiten',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);

                      _deleteEvent(event);
                    },
                    icon: const Icon(
                      Icons.delete,
                    ),
                    label: const Text(
                      'Termin löschen',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A1F44);
    const blue = Color(0xFF0B4EA2);
    const red = Color(0xFFE30613);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F5F7),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 70,
                    color: red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Termine konnten nicht geladen werden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _loadEvents,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Erneut versuchen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: RefreshIndicator(
        onRefresh: _loadEvents,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [navy, blue],
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
                        width: 48,
                        height: 48,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Image.asset(
                          'assets/branding/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Termine',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Übersichtlich und aktuell',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
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
                            backgroundColor: Colors.white,
                            foregroundColor: red,
                          ),
                          icon: const Icon(Icons.add),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
              child: _events.isEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 54,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0xFFE3E8EE),
                        ),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.calendar_month_outlined,
                            size: 72,
                            color: red,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Noch keine Termine vorhanden.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: navy,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: _events.map((event) {
                        final start = _parseDate(event['starts_at']);
                        final end = _parseDate(event['ends_at']);
                        final type =
                            event['event_type']?.toString() ?? 'dienst';
                        final status =
                            _attendanceByEvent[event['id']?.toString()];
                        final statusColor = _attendanceColor(status);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 13),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFFE3E8EE),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                blurRadius: 12,
                                offset: Offset(0, 4),
                                color: Color(0x0D000000),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () => _showDetails(event),
                            borderRadius: BorderRadius.circular(22),
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 66,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF4F7FA),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          start == null
                                              ? '--'
                                              : start.day
                                                  .toString()
                                                  .padLeft(2, '0'),
                                          style: const TextStyle(
                                            color: navy,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w900,
                                            height: 1,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _monthShort(start),
                                          style: const TextStyle(
                                            color: red,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                event['title']?.toString() ??
                                                    'Termin',
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w800,
                                                  color: navy,
                                                ),
                                              ),
                                            ),
                                            const Icon(
                                              Icons.chevron_right,
                                              color: Color(0xFF7E8996),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _typeName(type),
                                          style: const TextStyle(
                                            color: blue,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.schedule,
                                              size: 17,
                                              color: Color(0xFF73808F),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              end == null
                                                  ? '${_time(start)} Uhr'
                                                  : '${_time(start)} – ${_time(end)} Uhr',
                                              style: const TextStyle(
                                                color: Color(0xFF4B5563),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if ((event['location'] ?? '')
                                            .toString()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.location_on_outlined,
                                                size: 17,
                                                color: Color(0xFF73808F),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  event['location'].toString(),
                                                  style: const TextStyle(
                                                    color: Color(0xFF4B5563),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Container(
                                              width: 9,
                                              height: 9,
                                              decoration: BoxDecoration(
                                                color: statusColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: Text(
                                                _attendanceLabel(status),
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
          ? FloatingActionButton(
              onPressed: () => _openEditor(),
              backgroundColor: red,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
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
  State<EventEditor> createState() {
    return _EventEditorState();
  }
}

class _EventEditorState extends State<EventEditor> {
  final SupabaseClient _supabase = Supabase.instance.client;

  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _meetingPoint;
  late final TextEditingController _equipment;

  String _type = 'dienst';

  DateTime _start = DateTime.now().add(
    const Duration(hours: 1),
  );

  DateTime? _end;

  bool _saving = false;

  bool get _editing {
    return widget.event != null;
  }

  @override
  void initState() {
    super.initState();

    final event = widget.event;

    _title = TextEditingController(
      text: event?['title']?.toString() ?? '',
    );

    _description = TextEditingController(
      text: event?['description']?.toString() ?? '',
    );

    _location = TextEditingController(
      text: event?['location']?.toString() ?? '',
    );

    _meetingPoint = TextEditingController(
      text: event?['meeting_point']?.toString() ?? '',
    );

    _equipment = TextEditingController(
      text: event?['required_equipment']?.toString() ?? '',
    );

    if (event != null) {
      _type = event['event_type']?.toString() ?? 'dienst';

      _start = DateTime.tryParse(
            event['starts_at']?.toString() ?? '',
          )?.toLocal() ??
          _start;

      _end = DateTime.tryParse(
        event['ends_at']?.toString() ?? '',
      )?.toLocal();
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
    String two(int value) {
      return value.toString().padLeft(2, '0');
    }

    return '${two(date.day)}.${two(date.month)}.${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Future<DateTime?> _selectDateTime(
    DateTime initial,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(
        const Duration(days: 365),
      ),
      lastDate: DateTime.now().add(
        const Duration(days: 3650),
      ),
    );

    if (date == null || !mounted) {
      return null;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        initial,
      ),
    );

    if (time == null) {
      return null;
    }

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
        const SnackBar(
          content: Text(
            'Bitte einen Titel eingeben.',
          ),
        ),
      );

      return;
    }

    if (_end != null && _end!.isBefore(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Die Endzeit darf nicht vor der Startzeit liegen.',
          ),
        ),
      );

      return;
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      return;
    }

    setState(() {
      _saving = true;
    });

    final data = {
      'title': _title.text.trim(),
      'description':
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      'event_type': _type,
      'starts_at': _start.toUtc().toIso8601String(),
      'ends_at': _end?.toUtc().toIso8601String(),
      'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
      'meeting_point':
          _meetingPoint.text.trim().isEmpty ? null : _meetingPoint.text.trim(),
      'required_equipment':
          _equipment.text.trim().isEmpty ? null : _equipment.text.trim(),
    };

    try {
      if (_editing) {
        await _supabase.from('events').update(data).eq(
              'id',
              widget.event!['id'],
            );

        try {
          final startLocal = _start.toLocal();
          final dateText = '${startLocal.day.toString().padLeft(2, '0')}.'
              '${startLocal.month.toString().padLeft(2, '0')}.'
              '${startLocal.year} um '
              '${startLocal.hour.toString().padLeft(2, '0')}:'
              '${startLocal.minute.toString().padLeft(2, '0')} Uhr';

          await _supabase.functions.invoke(
            'send-push',
            body: {
              'title': 'Termin geändert',
              'body': '${_title.text.trim()} – $dateText',
            },
          );
        } catch (pushError) {
          debugPrint(
            'Termin geändert, Push fehlgeschlagen: $pushError',
          );
        }
      } else {
        await _supabase.from('events').insert({
          ...data,
          'created_by': user.id,
        });

        try {
          final startLocal = _start.toLocal();
          final dateText = '${startLocal.day.toString().padLeft(2, '0')}.'
              '${startLocal.month.toString().padLeft(2, '0')}.'
              '${startLocal.year} um '
              '${startLocal.hour.toString().padLeft(2, '0')}:'
              '${startLocal.minute.toString().padLeft(2, '0')} Uhr';

          await _supabase.functions.invoke(
            'send-push',
            body: {
              'title': 'Neuer Termin',
              'body': '${_title.text.trim()} – $dateText',
            },
          );
        } catch (pushError) {
          debugPrint('Termin gespeichert, Push fehlgeschlagen: $pushError');
        }
      }

      if (!mounted) return;

      Navigator.pop(
        context,
        true,
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Speichern fehlgeschlagen: $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _editing ? 'Termin bearbeiten' : 'Neuen Termin erstellen',
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Titel',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Art des Termins',
                border: OutlineInputBorder(),
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
                if (value != null) {
                  setState(() {
                    _type = value;
                  });
                }
              },
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.event,
              ),
              title: const Text(
                'Beginn',
              ),
              subtitle: Text(
                _formatDateTime(_start),
              ),
              trailing: const Icon(
                Icons.edit,
              ),
              onTap: () async {
                final selected = await _selectDateTime(
                  _start,
                );

                if (selected != null) {
                  setState(() {
                    _start = selected;
                  });
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.event_available,
              ),
              title: const Text(
                'Ende',
              ),
              subtitle: Text(
                _end == null ? 'Nicht angegeben' : _formatDateTime(_end!),
              ),
              trailing: _end == null
                  ? const Icon(Icons.add)
                  : IconButton(
                      icon: const Icon(
                        Icons.clear,
                      ),
                      onPressed: () {
                        setState(() {
                          _end = null;
                        });
                      },
                    ),
              onTap: () async {
                final selected = await _selectDateTime(
                  _end ??
                      _start.add(
                        const Duration(hours: 2),
                      ),
                );

                if (selected != null) {
                  setState(() {
                    _end = selected;
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: 'Ort',
                border: OutlineInputBorder(),
                prefixIcon: Icon(
                  Icons.location_on,
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _meetingPoint,
              decoration: const InputDecoration(
                labelText: 'Treffpunkt',
                border: OutlineInputBorder(),
                prefixIcon: Icon(
                  Icons.groups,
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _equipment,
              decoration: const InputDecoration(
                labelText: 'Benötigte Ausrüstung',
                border: OutlineInputBorder(),
                prefixIcon: Icon(
                  Icons.backpack,
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _description,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Beschreibung',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(),
                      )
                    : const Icon(
                        Icons.save,
                      ),
                label: Text(
                  _editing ? 'Änderungen speichern' : 'Termin erstellen',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: const Color(0xFFE30613),
            ),
            const SizedBox(height: 6),
            Text(
              value.toString(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 15,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFFE30613),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
