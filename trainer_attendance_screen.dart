
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/app_service.dart';

class TrainerAttendanceScreen extends StatefulWidget {
  const TrainerAttendanceScreen({super.key});
  @override
  State<TrainerAttendanceScreen> createState() => _TrainerAttendanceScreenState();
}

class _TrainerAttendanceScreenState extends State<TrainerAttendanceScreen> {
  List<JfEvent> events = [];
  JfEvent? selected;
  bool loading = true;
  List<Map<String,dynamic>> attendance = [];

  @override
  void initState() {
    super.initState();
    loadEvents();
  }

  Future<void> loadEvents() async {
    events = await AppService.events();
    if (events.isNotEmpty) {
      selected = events.first;
      await loadAttendance();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> loadAttendance() async {
    if (selected == null) return;
    attendance = await AppService.attendanceForEvent(selected!.id);
    if (mounted) setState(() {});
  }

  Future<void> update(Map<String,dynamic> row, String status) async {
    await AppService.updateAttendanceForUser(
      eventId: selected!.id,
      userId: row['user_id'],
      status: status,
      note: row['note'],
    );
    await loadAttendance();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anwesenheit')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<JfEvent>(
                    value: selected,
                    decoration: const InputDecoration(labelText: 'Termin'),
                    items: events.map((e) => DropdownMenuItem(
                      value: e,
                      child: Text('${DateFormat('dd.MM.yyyy').format(e.startsAt)} · ${e.title}'),
                    )).toList(),
                    onChanged: (e) async {
                      setState(() => selected = e);
                      await loadAttendance();
                    },
                  ),
                ),
                Expanded(
                  child: attendance.isEmpty
                      ? const Center(child: Text('Noch keine Rückmeldungen vorhanden.'))
                      : ListView.builder(
                          itemCount: attendance.length,
                          itemBuilder: (_, i) {
                            final r = attendance[i];
                            final p = r['profiles'] ?? {};
                            final name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              child: ListTile(
                                title: Text(name.isEmpty ? r['user_id'] : name),
                                subtitle: Text('Status: ${r['status']}'),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) => update(r, v),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'zugesagt', child: Text('Zugesagt')),
                                    PopupMenuItem(value: 'abgesagt', child: Text('Abgesagt')),
                                    PopupMenuItem(value: 'entschuldigt', child: Text('Entschuldigt')),
                                    PopupMenuItem(value: 'offen', child: Text('Offen')),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
