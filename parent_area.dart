import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/app_service.dart';

class ParentArea extends StatelessWidget {
  const ParentArea({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('👨‍👩‍👧 Elternbereich')),
      body: FutureBuilder<List<Profile>>(
        future: AppService.linkedChildren(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }

          final children = snapshot.data ?? [];
          if (children.isEmpty) {
            return const Center(
              child: Text('Noch kein Jugendmitglied mit diesem Elternkonto verknüpft.'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: children
                .map(
                  (child) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(child.name),
                      subtitle: const Text('Jugendmitglied'),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}
