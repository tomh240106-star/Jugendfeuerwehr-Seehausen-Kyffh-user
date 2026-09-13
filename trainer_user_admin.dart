
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/app_service.dart';

class TrainerUserAdmin extends StatefulWidget {
  const TrainerUserAdmin({super.key});
  @override
  State<TrainerUserAdmin> createState() => _TrainerUserAdminState();
}

class _TrainerUserAdminState extends State<TrainerUserAdmin> {
  late Future<List<Profile>> future;

  @override
  void initState() {
    super.initState();
    future = AppService.allProfiles();
  }

  void refresh() => setState(() => future = AppService.allProfiles());

  Future<void> changeRole(Profile p, String role) async {
    await AppService.setUserRole(p.id, role);
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benutzer verwalten')),
      body: FutureBuilder<List<Profile>>(
        future: future,
        builder: (_, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(
            children: s.data!.map((p) => Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(p.name.isEmpty ? p.id : p.name),
                subtitle: Text('Rolle: ${p.role}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => changeRole(p, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'jugendmitglied', child: Text('Jugendmitglied')),
                    PopupMenuItem(value: 'eltern', child: Text('Eltern')),
                    PopupMenuItem(value: 'ausbilder', child: Text('Ausbilder')),
                  ],
                ),
              ),
            )).toList(),
          );
        },
      ),
    );
  }
}
