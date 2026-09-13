import 'package:flutter/material.dart';
import '../services/app_service.dart';

class TrainerEventForm extends StatefulWidget {
  const TrainerEventForm({super.key});

  @override
  State<TrainerEventForm> createState() => _TrainerEventFormState();
}

class _TrainerEventFormState extends State<TrainerEventForm> {
  final title = TextEditingController();
  final description = TextEditingController();
  final location = TextEditingController();
  final meetingPoint = TextEditingController();
  final equipment = TextEditingController();

  String type = 'dienst';
  DateTime startsAt = DateTime.now().add(const Duration(days: 1));

  Future<void> save() async {
    if (title.text.trim().isEmpty) return;

    await AppService.createEvent(
      title: title.text.trim(),
      type: type,
      startsAt: startsAt,
      description: description.text.trim(),
      location: location.text.trim(),
      meetingPoint: meetingPoint.text.trim(),
      equipment: equipment.text.trim(),
    );

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Termin erstellen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Titel')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: type,
            decoration: const InputDecoration(labelText: 'Art'),
            items: const [
              DropdownMenuItem(value: 'dienst', child: Text('Dienst')),
              DropdownMenuItem(value: 'veranstaltung', child: Text('Veranstaltung')),
              DropdownMenuItem(value: 'wettbewerb', child: Text('Wettbewerb')),
              DropdownMenuItem(value: 'zeltlager', child: Text('Zeltlager')),
              DropdownMenuItem(value: 'elternabend', child: Text('Elternabend')),
              DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges')),
            ],
            onChanged: (v) => setState(() => type = v ?? 'dienst'),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start'),
            subtitle: Text(startsAt.toString()),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: startsAt,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (d == null || !mounted) return;

              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(startsAt),
              );
              if (t == null) return;

              setState(() {
                startsAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
              });
            },
          ),
          TextField(controller: location, decoration: const InputDecoration(labelText: 'Ort')),
          const SizedBox(height: 10),
          TextField(controller: meetingPoint, decoration: const InputDecoration(labelText: 'Treffpunkt')),
          const SizedBox(height: 10),
          TextField(controller: equipment, decoration: const InputDecoration(labelText: 'Benötigte Ausrüstung')),
          const SizedBox(height: 10),
          TextField(
            controller: description,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Beschreibung'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: save,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE30613)),
            child: const Text('Termin speichern'),
          ),
        ],
      ),
    );
  }
}
