
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/app_service.dart';

class TrainerParentLinkScreen extends StatefulWidget {
  const TrainerParentLinkScreen({super.key});
  @override
  State<TrainerParentLinkScreen> createState() => _TrainerParentLinkScreenState();
}

class _TrainerParentLinkScreenState extends State<TrainerParentLinkScreen> {
  List<Profile> parents = [];
  List<Profile> children = [];
  List<Map<String,dynamic>> links = [];
  String? parentId;
  String? childId;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final profiles = await AppService.allProfiles();
    links = await AppService.allParentChildLinks();
    parents = profiles.where((p) => p.role == 'eltern').toList();
    children = profiles.where((p) => p.role == 'jugendmitglied').toList();
    if (mounted) setState(() => loading = false);
  }

  Future<void> add() async {
    if (parentId == null || childId == null) return;
    await AppService.linkParentChild(parentId: parentId!, childId: childId!);
    await load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eltern-Kind-Verknüpfungen')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                DropdownButtonFormField<String>(
                  value: parentId,
                  decoration: const InputDecoration(labelText: 'Elternkonto'),
                  items: parents.map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name),
                  )).toList(),
                  onChanged: (v) => setState(() => parentId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: childId,
                  decoration: const InputDecoration(labelText: 'Jugendmitglied'),
                  items: children.map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name),
                  )).toList(),
                  onChanged: (v) => setState(() => childId = v),
                ),
                const SizedBox(height: 10),
                FilledButton(onPressed: add, child: const Text('Verknüpfen')),
                const SizedBox(height: 20),
                const Text('Bestehende Verknüpfungen', style: TextStyle(fontWeight: FontWeight.bold)),
                ...links.map((l) {
                  final parent = l['parent'] ?? {};
                  final child = l['child'] ?? {};
                  final pName = '${parent['first_name'] ?? ''} ${parent['last_name'] ?? ''}'.trim();
                  final cName = '${child['first_name'] ?? ''} ${child['last_name'] ?? ''}'.trim();
                  return Card(
                    child: ListTile(
                      title: Text('$pName → $cName'),
                      trailing: IconButton(
                        icon: const Icon(Icons.link_off),
                        onPressed: () async {
                          await AppService.unlinkParentChild(
                            parentId: l['parent_id'],
                            childId: l['child_id'],
                          );
                          await load();
                        },
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
