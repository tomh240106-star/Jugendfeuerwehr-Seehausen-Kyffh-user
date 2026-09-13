
import 'package:flutter/material.dart';
import '../services/app_service.dart';
import '../services/document_service.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late Future<List<Map<String, dynamic>>> future;
  String? role;

  @override
  void initState() {
    super.initState();
    future = DocumentService.listDocuments();
    AppService.myProfile().then((p) {
      if (mounted) setState(() => role = p?.role);
    });
  }

  void refresh() => setState(() => future = DocumentService.listDocuments());

  Future<void> upload() async {
    final title = TextEditingController();
    final category = TextEditingController(text: 'Allgemein');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Dokument hochladen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Titel')),
            TextField(controller: category, decoration: const InputDecoration(labelText: 'Kategorie')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Datei wählen')),
        ],
      ),
    );

    if (ok == true && title.text.trim().isNotEmpty) {
      await DocumentService.pickAndUpload(
        title: title.text.trim(),
        category: category.text.trim(),
      );
      refresh();
    }
  }

  Future<void> openDoc(Map<String,dynamic> d) async {
    final url = await DocumentService.signedUrl(d['storage_path']);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(d['title'] ?? 'Dokument'),
        content: SelectableText(
          'Temporärer Download-Link (10 Minuten gültig):\n\n$url',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📄 Dokumente'),
        actions: [
          if (role == 'ausbilder')
            IconButton(onPressed: upload, icon: const Icon(Icons.upload_file)),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) return Center(child: Text('Fehler: ${s.error}'));

          final docs = s.data ?? [];
          if (docs.isEmpty) return const Center(child: Text('Noch keine Dokumente vorhanden.'));

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text(d['title'] ?? d['file_name'] ?? 'Dokument'),
                  subtitle: Text(d['category'] ?? 'Allgemein'),
                  onTap: () => openDoc(d),
                  trailing: role == 'ausbilder'
                      ? PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'delete') {
                              await DocumentService.deleteDocument(
                                d['id'],
                                d['storage_path'],
                              );
                              refresh();
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'delete', child: Text('Löschen')),
                          ],
                        )
                      : const Icon(Icons.chevron_right),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: role == 'ausbilder'
          ? FloatingActionButton(
              onPressed: upload,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
