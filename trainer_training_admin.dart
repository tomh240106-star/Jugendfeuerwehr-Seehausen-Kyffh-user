
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/app_service.dart';

class TrainerTrainingAdmin extends StatefulWidget {
  const TrainerTrainingAdmin({super.key});
  @override
  State<TrainerTrainingAdmin> createState() => _TrainerTrainingAdminState();
}

class _TrainerTrainingAdminState extends State<TrainerTrainingAdmin> {
  late Future<List<TrainingPlan>> future;

  @override
  void initState() {
    super.initState();
    future = AppService.trainingPlans();
  }

  void refresh() => setState(() => future = AppService.trainingPlans());

  Future<void> createPlan() async {
    final title = TextEditingController();
    final desc = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ausbildungsplan erstellen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Titel')),
            TextField(controller: desc, decoration: const InputDecoration(labelText: 'Beschreibung')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
        ],
      ),
    );

    if (ok == true && title.text.trim().isNotEmpty) {
      await AppService.createTrainingPlan(title: title.text.trim(), description: desc.text.trim());
      refresh();
    }
  }

  Future<void> addUnit(TrainingPlan plan) async {
    final title = TextEditingController();
    final topic = TextEditingController();
    final objectives = TextEditingController();
    final equipment = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Einheit zu "${plan.title}"'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Titel')),
              TextField(controller: topic, decoration: const InputDecoration(labelText: 'Thema')),
              TextField(controller: objectives, decoration: const InputDecoration(labelText: 'Lernziele')),
              TextField(controller: equipment, decoration: const InputDecoration(labelText: 'Ausrüstung')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
        ],
      ),
    );

    if (ok == true && title.text.trim().isNotEmpty) {
      await AppService.createTrainingUnit(
        planId: plan.id,
        title: title.text.trim(),
        topic: topic.text.trim(),
        objectives: objectives.text.trim(),
        equipment: equipment.text.trim(),
        sortOrder: plan.units.length,
      );
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ausbildungsplan verwalten'),
        actions: [IconButton(onPressed: createPlan, icon: const Icon(Icons.add))],
      ),
      body: FutureBuilder<List<TrainingPlan>>(
        future: future,
        builder: (_, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final plans = s.data!;
          if (plans.isEmpty) return const Center(child: Text('Noch keine Ausbildungspläne.'));
          return ListView(
            padding: const EdgeInsets.all(12),
            children: plans.map((p) => Card(
              child: ExpansionTile(
                title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(p.description ?? ''),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'add') await addUnit(p);
                    if (v == 'delete') {
                      await AppService.deleteTrainingPlan(p.id);
                      refresh();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'add', child: Text('Einheit hinzufügen')),
                    PopupMenuItem(value: 'delete', child: Text('Plan löschen')),
                  ],
                ),
                children: p.units.map((u) => ListTile(
                  leading: const Icon(Icons.local_fire_department),
                  title: Text(u.title),
                  subtitle: Text([u.topic, u.objectives, u.equipment]
                      .where((x) => x != null && x!.isNotEmpty)
                      .join('\n')),
                )).toList(),
              ),
            )).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: createPlan,
        child: const Icon(Icons.add),
      ),
    );
  }
}
