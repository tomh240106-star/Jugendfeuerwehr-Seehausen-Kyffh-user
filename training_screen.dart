import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/app_service.dart';

class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📚 Ausbildungsplan')),
      body: FutureBuilder<List<TrainingPlan>>(
        future: AppService.trainingPlans(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }

          final plans = snapshot.data ?? [];
          if (plans.isEmpty) {
            return const Center(child: Text('Noch kein Ausbildungsplan vorhanden.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: plans.length,
            itemBuilder: (_, i) {
              final p = plans[i];

              return Card(
                child: ExpansionTile(
                  title: Text(
                    p.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(p.description ?? ''),
                  children: p.units
                      .map(
                        (u) => ListTile(
                          leading: const Icon(Icons.local_fire_department),
                          title: Text(u.title),
                          subtitle: Text([
                            u.topic,
                            u.objectives,
                            u.equipment,
                          ].where((x) => x != null && x!.isNotEmpty).join('\n')),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
