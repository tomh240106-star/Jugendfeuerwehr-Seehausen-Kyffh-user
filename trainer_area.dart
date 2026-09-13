
import 'package:flutter/material.dart';
import 'trainer_event_form.dart';
import 'trainer_attendance_screen.dart';
import 'trainer_training_admin.dart';
import 'trainer_user_admin.dart';
import 'trainer_parent_link_screen.dart';
import 'trainer_push_screen.dart';

class TrainerArea extends StatelessWidget {
  const TrainerArea({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('👨‍🚒 Ausbilderbereich')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [

          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active),
              title: const Text('Push-Nachricht senden'),
              subtitle: const Text('An einzelne Benutzer oder alle Geräte'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrainerPushScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_available),
              title: const Text('Termin erstellen'),
              subtitle: const Text('Neue Dienste, Veranstaltungen und Wettbewerbe'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrainerEventForm()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.how_to_reg),
              title: const Text('Anwesenheit verwalten'),
              subtitle: const Text('Zu-/Absagen prüfen und ändern'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrainerAttendanceScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('Ausbildungsplan verwalten'),
              subtitle: const Text('Pläne und Ausbildungseinheiten erstellen'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrainerTrainingAdmin()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.family_restroom),
              title: const Text('Eltern-Kind-Verknüpfungen'),
              subtitle: const Text('Elternkonten mit Jugendmitgliedern verbinden'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrainerParentLinkScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: const Text('Benutzer verwalten'),
              subtitle: const Text('Rollen prüfen und Ausbilder freischalten'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrainerUserAdmin()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
