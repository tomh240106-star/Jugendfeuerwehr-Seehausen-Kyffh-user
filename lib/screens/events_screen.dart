import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _supabase
          .from('events')
          .select()
          .order('start_at', ascending: true);

      final data = List<Map<String, dynamic>>.from(response);

      if (!mounted) return;

      setState(() {
        _events = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _readString(
    Map<String, dynamic> event,
    List<String> possibleKeys,
  ) {
    for (final key in possibleKeys) {
      final value = event[key];

      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }

    return '';
  }

  DateTime? _readDate(
    Map<String, dynamic> event,
    List<String> possibleKeys,
  ) {
    for (final key in possibleKeys) {
      final value = event[key];

      if (value == null) continue;

      if (value is DateTime) {
        return value.toLocal();
      }

      final parsed = DateTime.tryParse(value.toString());

      if (parsed != null) {
        return parsed.toLocal();
      }
    }

    return null;
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Datum nicht angegeben';
    }

    return DateFormat(
      'dd.MM.yyyy',
      'de_DE',
    ).format(date);
  }

  String _formatTime(DateTime? date) {
    if (date == null) {
      return '--:--';
    }

    return DateFormat(
      'HH:mm',
      'de_DE',
    ).format(date);
  }

  String _eventTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'dienst':
        return 'Dienst';

      case 'ausbildung':
        return 'Ausbildung';

      case 'wettbewerb':
        return 'Wettbewerb';

      case 'veranstaltung':
        return 'Veranstaltung';

      case 'zeltlager':
        return 'Zeltlager';

      case 'elternabend':
        return 'Elternabend';

      default:
        if (type.isEmpty) {
          return 'Termin';
        }

        return type;
    }
  }

  IconData _eventIcon(String type) {
    switch (type.toLowerCase()) {
      case 'ausbildung':
        return Icons.school;

      case 'wettbewerb':
        return Icons.emoji_events;

      case 'veranstaltung':
        return Icons.celebration;

      case 'zeltlager':
        return Icons.cabin;

      case 'elternabend':
        return Icons.groups;

      default:
        return Icons.local_fire_department;
    }
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
              const SizedBox(height: 20),
              const Text(
                'Termine konnten nicht geladen werden.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadEvents,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    if (_events.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadEvents,
        child: ListView(
          children: const [
            SizedBox(height: 150),
            Icon(
              Icons.calendar_month_outlined,
              size: 90,
              color: Color(0xFFE30613),
            ),
            SizedBox(height: 20),
            Center(
              child: Text(
                'Noch keine Termine eingetragen.',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(height: 10),
            Center(
              child: Text(
                'Neue Dienste und Veranstaltungen erscheinen hier.',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];

          final title = _readString(
            event,
            [
              'title',
              'name',
            ],
          );

          final description = _readString(
            event,
            [
              'description',
              'notes',
            ],
          );

          final location = _readString(
            event,
            [
              'location',
              'place',
              'ort',
            ],
          );

          final meetingPoint = _readString(
            event,
            [
              'meeting_point',
              'meetingPoint',
              'treffpunkt',
            ],
          );

          final equipment = _readString(
            event,
            [
              'equipment',
              'required_equipment',
              'ausruestung',
            ],
          );

          final type = _readString(
            event,
            [
              'event_type',
              'type',
            ],
          );

          final start = _readDate(
            event,
            [
              'start_at',
              'start_time',
              'starts_at',
              'date',
            ],
          );

          final end = _readDate(
            event,
            [
              'end_at',
              'end_time',
              'ends_at',
            ],
          );

          return Card(
            margin: const EdgeInsets.only(
              bottom: 14,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _showEventDetails(
                  context,
                  event,
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE30613),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _eventIcon(type),
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isEmpty
                                ? _eventTypeLabel(type)
                                : title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _eventTypeLabel(type),
                            style: const TextStyle(
                              color: Color(0xFFE30613),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDate(start),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                end == null
                                    ? _formatTime(start)
                                    : '${_formatTime(start)} - ${_formatTime(end)}',
                              ),
                            ],
                          ),
                          if (location.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(location),
                                ),
                              ],
                            ),
                          ],
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
    );
  }

  void _showEventDetails(
    BuildContext context,
    Map<String, dynamic> event,
  ) {
    final title = _readString(
      event,
      [
        'title',
        'name',
      ],
    );

    final type = _readString(
      event,
      [
        'event_type',
        'type',
      ],
    );

    final description = _readString(
      event,
      [
        'description',
        'notes',
      ],
    );

    final location = _readString(
      event,
      [
        'location',
        'place',
        'ort',
      ],
    );

    final meetingPoint = _readString(
      event,
      [
        'meeting_point',
        'meetingPoint',
        'treffpunkt',
      ],
    );

    final equipment = _readString(
      event,
      [
        'equipment',
        'required_equipment',
        'ausruestung',
      ],
    );

    final start = _readDate(
      event,
      [
        'start_at',
        'start_time',
        'starts_at',
        'date',
      ],
    );

    final end = _readDate(
      event,
      [
        'end_at',
        'end_time',
        'ends_at',
      ],
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  title.isEmpty
                      ? _eventTypeLabel(type)
                      : title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _eventTypeLabel(type),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFFE30613),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                _DetailRow(
                  icon: Icons.calendar_today,
                  title: 'Datum',
                  value: _formatDate(start),
                ),
                _DetailRow(
                  icon: Icons.access_time,
                  title: 'Uhrzeit',
                  value: end == null
                      ? _formatTime(start)
                      : '${_formatTime(start)} - ${_formatTime(end)}',
                ),
                if (location.isNotEmpty)
                  _DetailRow(
                    icon: Icons.location_on,
                    title: 'Ort',
                    value: location,
                  ),
                if (meetingPoint.isNotEmpty)
                  _DetailRow(
                    icon: Icons.groups,
                    title: 'Treffpunkt',
                    value: meetingPoint,
                  ),
                if (equipment.isNotEmpty)
                  _DetailRow(
                    icon: Icons.backpack,
                    title: 'Ausrüstung',
                    value: equipment,
                  ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Beschreibung',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 16,
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Schließen'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
        bottom: 16,
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
