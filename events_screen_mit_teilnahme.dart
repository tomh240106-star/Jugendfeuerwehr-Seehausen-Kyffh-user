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

    final role = profile?['role']
        ?.toString()
        .trim()
        .toLowerCase();

    setState(() {
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
        return 'Vielleicht / noch offen';
    }
  }

  IconData _attendanceIcon(String? status) {
    switch (status) {
      case 'zugesagt':
        return Icons.check_circle;
      case 'abgesagt':
        return Icons.cancel;
      case 'entschuldigt':
        return Icons.info;
      default:
        return Icons.help_outline;
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

  IconData _typeIcon(String type) {
    switch (type) {
      case 'wettbewerb':
        return Icons.emoji_events;

      case 'zeltlager':
        return Icons.cabin;

      case 'elternabend':
        return Icons.groups;

      case 'veranstaltung':
        return Icons.celebration;

      default:
        return Icons.local_fire_department;
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
      await _supabase
          .from('events')
          .delete()
          .eq(
            'id',
            event['id'],
          );

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

              if ((event['location'] ?? '')
                  .toString()
                  .isNotEmpty)
                _DetailRow(
                  icon: Icons.location_on,
                  title: 'Ort',
                  value: event['location'].toString(),
                ),

              if ((event['meeting_point'] ?? '')
                  .toString()
                  .isNotEmpty)
                _DetailRow(
                  icon: Icons.groups,
                  title: 'Treffpunkt',
                  value: event['meeting_point'].toString(),
                ),

              if ((event['required_equipment'] ?? '')
                  .toString()
                  .isNotEmpty)
                _DetailRow(
                  icon: Icons.backpack,
                  title: 'Ausrüstung',
                  value: event['required_equipment'].toString(),
                ),

              if ((event['description'] ?? '')
                  .toString()
                  .isNotEmpty) ...[
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
                    selected:
                        _attendanceByEvent[event['id']?.toString()] == 'zugesagt',
                    onSelected: (_) {
                      _setAttendance(event, 'zugesagt');
                      Navigator.pop(context);
                    },
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.cancel, size: 18),
                    label: const Text('Ich nehme nicht teil'),
                    selected:
                        _attendanceByEvent[event['id']?.toString()] == 'abgesagt',
                    onSelected: (_) {
                      _setAttendance(event, 'abgesagt');
                      Navigator.pop(context);
                    },
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.help_outline, size: 18),
                    label: const Text('Vielleicht'),
                    selected:
                        _attendanceByEvent[event['id']?.toString()] == 'offen',
                    onSelected: (_) {
                      _setAttendance(event, 'offen');
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),

              if (_isTrainer) ...[
                const SizedBox(height: 30),

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
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 70,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Termine konnten nicht geladen werden.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
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
                icon: const Icon(
                  Icons.refresh,
                ),
                label: const Text(
                  'Erneut versuchen',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadEvents,
        child: _events.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 150),
                  Icon(
                    Icons.calendar_month,
                    size: 90,
                    color: Color(0xFFE30613),
                  ),
                  SizedBox(height: 20),
                  Center(
                    child: Text(
                      'Noch keine Termine vorhanden.',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _events.length,
                itemBuilder: (
                  context,
                  index,
                ) {
                  final event = _events[index];

                  final start = _parseDate(
                    event['starts_at'],
                  );

                  final end = _parseDate(
                    event['ends_at'],
                  );

                  final type =
                      event['event_type']?.toString() ??
                          'dienst';

                  return Card(
                    margin: const EdgeInsets.only(
                      bottom: 14,
                    ),
                    child: InkWell(
                      onTap: () {
                        _showDetails(event);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor:
                                  const Color(0xFFE30613),
                              foregroundColor:
                                  Colors.white,
                              child: Icon(
                                _typeIcon(type),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event['title']
                                            ?.toString() ??
                                        'Termin',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _typeName(type),
                                    style: const TextStyle(
                                      color:
                                          Color(0xFFE30613),
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '${_date(start)} · ${_time(start)}',
                                  ),
                                  if (end != null)
                                    Text(
                                      'Ende: ${_time(end)}',
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _attendanceIcon(
                                            _attendanceByEvent[
                                                event['id']?.toString()],
                                          ),
                                          size: 17,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            _attendanceLabel(
                                              _attendanceByEvent[
                                                  event['id']?.toString()],
                                            ),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if ((event['location'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(
                                        top: 5,
                                      ),
                                      child: Text(
                                        event['location']
                                            .toString(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),

      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ),
        color: const Color(0xFFF3F5F7),
        child: Text(
          _isTrainer
              ? 'Rolle erkannt: Ausbilder'
              : 'Rolle erkannt: kein Ausbilder',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: _isTrainer ? Colors.green : Colors.red,
          ),
        ),
      ),

      floatingActionButton: _isTrainer
          ? FloatingActionButton.extended(
              onPressed: () {
                _openEditor();
              },
              backgroundColor: const Color(
                0xFFE30613,
              ),
              foregroundColor: Colors.white,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Termin',
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
  State<EventEditor> createState() {
    return _EventEditorState();
  }
}

class _EventEditorState extends State<EventEditor> {
  final SupabaseClient _supabase =
      Supabase.instance.client;

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
      _type =
          event['event_type']?.toString() ??
              'dienst';

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

    if (_end != null &&
        _end!.isBefore(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Die Endzeit darf nicht vor der Startzeit liegen.',
          ),
        ),
      );

      return;
    }

    final user =
        _supabase.auth.currentUser;

    if (user == null) {
      return;
    }

    setState(() {
      _saving = true;
    });

    final data = {
      'title': _title.text.trim(),
      'description':
          _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
      'event_type': _type,
      'starts_at': _start.toUtc().toIso8601String(),
      'ends_at': _end?.toUtc().toIso8601String(),
      'location':
          _location.text.trim().isEmpty
              ? null
              : _location.text.trim(),
      'meeting_point':
          _meetingPoint.text.trim().isEmpty
              ? null
              : _meetingPoint.text.trim(),
      'required_equipment':
          _equipment.text.trim().isEmpty
              ? null
              : _equipment.text.trim(),
    };

    try {
      if (_editing) {
        await _supabase
            .from('events')
            .update(data)
            .eq(
              'id',
              widget.event!['id'],
            );
      } else {
        await _supabase
            .from('events')
            .insert({
          ...data,
          'created_by': user.id,
        });
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
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              _editing
                  ? 'Termin bearbeiten'
                  : 'Neuen Termin erstellen',
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
              value: _type,
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
                final selected =
                    await _selectDateTime(
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
                _end == null
                    ? 'Nicht angegeben'
                    : _formatDateTime(_end!),
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
                final selected =
                    await _selectDateTime(
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
                onPressed:
                    _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(),
                      )
                    : const Icon(
                        Icons.save,
                      ),
                label: Text(
                  _editing
                      ? 'Änderungen speichern'
                      : 'Termin erstellen',
                ),
              ),
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
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFFE30613),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight:
                        FontWeight.bold,
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
