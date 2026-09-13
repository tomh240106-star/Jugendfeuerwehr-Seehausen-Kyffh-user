import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/app_service.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  Profile? profile;
  List<JfEvent> events = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      profile = await AppService.myProfile();
      events = await AppService.events();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = events.isEmpty ? null : events.first;

    return CustomScrollView(
      slivers: [
        const SliverAppBar(
          pinned: true,
          title: Text('🚒 Jugendfeuerwehr Seehausen/Kyffhäuser'),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                'Hallo${profile == null ? '' : ' ${profile!.firstName}'}! 👋',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const Text('Schön, dass du da bist.'),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📅 Nächster Termin',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      const SizedBox(height: 10),
                      if (loading) const CircularProgressIndicator(),
                      if (!loading && next == null) const Text('Noch keine Termine eingetragen.'),
                      if (next != null) _event(next),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(Icons.campaign)),
                  title: Text(
                    'Aktuelle Informationen',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('Wichtige Mitteilungen erscheinen hier.'),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _event(JfEvent e) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE30613),
        foregroundColor: Colors.white,
        child: Text(DateFormat('dd').format(e.startsAt)),
      ),
      title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        '${e.type} · ${DateFormat('dd.MM.yyyy HH:mm').format(e.startsAt)}\n${e.location ?? ''}',
      ),
    );
  }
}
