import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/app_service.dart';
import 'trainer_event_form.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsState();
}

class _EventsState extends State<EventsScreen> {
  late Future<List<JfEvent>> future;
  String? role;

  @override
  void initState() {
    super.initState();
    future = AppService.events();
    AppService.myProfile().then((p) {
      if (mounted) setState(() => role = p?.role);
    });
  }

  Future<void> refresh() async {
    setState(() => future = AppService.events());
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📅 Termine'),
        actions: [
          if (role == 'ausbilder')
            IconButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TrainerEventForm()),
                );
                refresh();
              },
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: FutureBuilder<List<JfEvent>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }

          final list = snapshot.data ?? [];
          if (list.isEmpty) return const Center(child: Text('Keine Termine vorhanden.'));

          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, i) => _card(list[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _card(JfEvent e) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFE30613),
                  foregroundColor: Colors.white,
                  child: Text(DateFormat('dd').format(e.startsAt)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${e.type} · ${DateFormat('dd.MM.yyyy HH:mm').format(e.startsAt)}'),
            if (e.location != null) Text('📍 ${e.location}'),
            if (e.description != null) Text(e.description!),
            if (e.equipment != null && e.equipment!.isNotEmpty) Text('🎒 ${e.equipment}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _att(e, 'zugesagt'),
                  child: const Text('✓ Ich nehme teil'),
                ),
                OutlinedButton(
                  onPressed: () => _att(e, 'abgesagt'),
                  child: const Text('✕ Absagen'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _att(JfEvent e, String status) async {
    await AppService.setAttendance(e.id, status);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(status == 'zugesagt' ? 'Teilnahme gespeichert.' : 'Absage gespeichert.'),
      ),
    );
  }
}
