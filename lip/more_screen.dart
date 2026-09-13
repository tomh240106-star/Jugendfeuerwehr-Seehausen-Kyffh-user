import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_service.dart';
import 'parent_area.dart';
import 'trainer_area.dart';
import 'documents_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String? role;

  @override
  void initState() {
    super.initState();
    AppService.myProfile().then((p) {
      if (mounted) setState(() => role = p?.role);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('☰ Mehr')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(Icons.person)),
              title: Text('Mein Profil'),
              subtitle: Text('Benutzerkonto & persönliche Daten'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Benachrichtigungen'),
              onTap: () => _notice(context),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Dokumente'),
              subtitle: const Text('Ausbildungsunterlagen und Informationen'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DocumentsScreen()),
              ),
            ),
          ),
          if (role == 'eltern')
            Card(
              child: ListTile(
                leading: const Icon(Icons.family_restroom),
                title: const Text('Elternbereich'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ParentArea()),
                ),
              ),
            ),
          if (role == 'ausbilder')
            Card(
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Ausbilderbereich'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TrainerArea()),
                ),
              ),
            ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('Datenschutz'),
              subtitle: Text('Datenschutzhinweise und Einwilligungen'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Abmelden'),
              onTap: () async => Supabase.instance.client.auth.signOut(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _notice(BuildContext context) async {
    try {
      final notifications = await AppService.notifications();
      if (!context.mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Benachrichtigungen'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: notifications.isEmpty
                ? const Center(child: Text('Keine Benachrichtigungen.'))
                : ListView(
                    children: notifications
                        .map(
                          (x) => ListTile(
                            title: Text(x['title'] ?? ''),
                            subtitle: Text(x['body'] ?? ''),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }
}
