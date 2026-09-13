
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/app_service.dart';
import '../services/push_admin_service.dart';

class TrainerPushScreen extends StatefulWidget {
  const TrainerPushScreen({super.key});

  @override
  State<TrainerPushScreen> createState() => _TrainerPushScreenState();
}

class _TrainerPushScreenState extends State<TrainerPushScreen> {
  final title = TextEditingController();
  final body = TextEditingController();
  List<Profile> people = [];
  String? selectedUserId;
  bool loading = true;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    AppService.allProfiles().then((list) {
      if (!mounted) return;
      setState(() {
        people = list;
        loading = false;
      });
    });
  }

  Future<void> send() async {
    if (title.text.trim().isEmpty || body.text.trim().isEmpty) return;

    setState(() => sending = true);
    try {
      await PushAdminService.sendPush(
        title: title.text.trim(),
        body: body.text.trim(),
        userId: selectedUserId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Push-Nachricht wurde versendet.')),
      );
      title.clear();
      body.clear();
      setState(() => selectedUserId = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Push-Nachricht senden')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String?>(
                  value: selectedUserId,
                  decoration: const InputDecoration(
                    labelText: 'Empfänger',
                    helperText: 'Leer lassen = alle registrierten Geräte',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Alle Benutzer'),
                    ),
                    ...people.map(
                      (p) => DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text('${p.name} (${p.role})'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => selectedUserId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Titel'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: body,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Nachricht'),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: sending ? null : send,
                  icon: const Icon(Icons.send),
                  label: Text(sending ? 'Wird gesendet...' : 'Push senden'),
                ),
              ],
            ),
    );
  }
}
