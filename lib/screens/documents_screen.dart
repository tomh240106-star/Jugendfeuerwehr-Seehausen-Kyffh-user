import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  bool _uploading = false;
  String? _error;
  List<Map<String, dynamic>> _documents = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadRole(),
      _loadDocuments(),
    ]);
  }

  Future<void> _loadRole() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _isTrainer =
            profile?['role']?.toString().trim().toLowerCase() == 'ausbilder';
      });
    } catch (_) {}
  }

  Future<void> _loadDocuments() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final rows = await _supabase
          .from('documents')
          .select()
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _documents = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _formatDate(dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (dt == null) return '';

    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  IconData _iconForFile(String fileName) {
    final name = fileName.toLowerCase();

    if (name.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (name.endsWith('.doc') || name.endsWith('.docx')) {
      return Icons.description;
    }
    if (name.endsWith('.xls') || name.endsWith('.xlsx')) {
      return Icons.table_chart;
    }
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp')) {
      return Icons.image;
    }

    return Icons.insert_drive_file;
  }

  String? _mimeTypeForFile(String fileName) {
    final name = fileName.toLowerCase();

    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.txt')) return 'text/plain';
    if (name.endsWith('.doc')) return 'application/msword';
    if (name.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (name.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (name.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }

    return 'application/octet-stream';
  }

  Future<void> _openDocument(Map<String, dynamic> document) async {
    try {
      final path = document['storage_path']?.toString();

      if (path == null || path.isEmpty) {
        throw Exception('Kein Speicherpfad vorhanden.');
      }

      final signedUrl = await _supabase.storage
          .from('documents')
          .createSignedUrl(path, 60);

      final uri = Uri.parse(signedUrl);

      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        throw Exception('Die Datei konnte nicht geöffnet werden.');
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dokument konnte nicht geöffnet werden: $e'),
        ),
      );
    }
  }

  Future<void> _uploadDocument() async {
    if (_uploading) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final pickedFile = result.files.single;

    if (pickedFile.path == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die ausgewählte Datei konnte nicht gelesen werden.'),
        ),
      );
      return;
    }

    if (!mounted) return;

    final meta = await showModalBottomSheet<_DocumentMeta>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DocumentMetaSheet(
        initialTitle: pickedFile.name,
      ),
    );

    if (meta == null) return;

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _uploading = true);

    String? uploadedPath;

    try {
      final safeName = pickedFile.name.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );

      final path =
          '${user.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName';

      uploadedPath = path;

      await _supabase.storage.from('documents').upload(
            path,
            File(pickedFile.path!),
            fileOptions: FileOptions(
              contentType: _mimeTypeForFile(pickedFile.name),
              upsert: false,
            ),
          );

      await _supabase.from('documents').insert({
        'title': meta.title,
        'category': meta.category,
        'file_name': pickedFile.name,
        'storage_path': path,
        'mime_type': _mimeTypeForFile(pickedFile.name),
        'uploaded_by': user.id,
      });

      try {
        await _supabase.functions.invoke(
          'send-push',
          body: {
            'title': 'Neues Dokument',
            'body': '${meta.title} – ${meta.category}',
          },
        );
      } catch (pushError) {
        debugPrint(
          'Dokument gespeichert, Push fehlgeschlagen: $pushError',
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dokument wurde hochgeladen.')),
      );

      await _loadDocuments();
    } catch (e) {
      if (uploadedPath != null) {
        try {
          await _supabase.storage
              .from('documents')
              .remove([uploadedPath]);
        } catch (_) {}
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _deleteDocument(Map<String, dynamic> document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dokument löschen?'),
        content: Text(
          '„${document['title'] ?? document['file_name'] ?? 'Dokument'}“ '
          'wird dauerhaft gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final path = document['storage_path']?.toString();

      if (path != null && path.isNotEmpty) {
        await _supabase.storage.from('documents').remove([path]);
      }

      await _supabase
          .from('documents')
          .delete()
          .eq('id', document['id']);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dokument gelöscht.')),
      );

      await _loadDocuments();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _loadDocuments,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            const Icon(Icons.error_outline, size: 70),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Dokumente konnten nicht geladen werden.\n\n$_error',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadDocuments,
        child: _documents.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 100),
                  Icon(
                    Icons.folder_open,
                    size: 90,
                    color: Color(0xFFE30613),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Noch keine Dokumente vorhanden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: _documents.length,
                itemBuilder: (context, index) {
                  final document = _documents[index];
                  final title = document['title']?.toString() ?? 'Dokument';
                  final fileName =
                      document['file_name']?.toString() ?? 'Datei';
                  final category =
                      document['category']?.toString() ?? 'Allgemein';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFE30613),
                        foregroundColor: Colors.white,
                        child: Icon(_iconForFile(fileName)),
                      ),
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '$category\n$fileName\n${_formatDate(document['created_at'])}',
                      ),
                      isThreeLine: true,
                      onTap: () => _openDocument(document),
                      trailing: _isTrainer
                          ? PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'open') {
                                  _openDocument(document);
                                } else if (value == 'delete') {
                                  _deleteDocument(document);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'open',
                                  child: ListTile(
                                    leading: Icon(Icons.open_in_new),
                                    title: Text('Öffnen'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline),
                                    title: Text('Löschen'),
                                  ),
                                ),
                              ],
                            )
                          : const Icon(Icons.open_in_new),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: _isTrainer
          ? FloatingActionButton.extended(
              onPressed: _uploading ? null : _uploadDocument,
              backgroundColor: const Color(0xFFE30613),
              foregroundColor: Colors.white,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_uploading ? 'Upload …' : 'Dokument'),
            )
          : null,
    );
  }
}

class _DocumentMeta {
  final String title;
  final String category;

  const _DocumentMeta({
    required this.title,
    required this.category,
  });
}

class _DocumentMetaSheet extends StatefulWidget {
  final String initialTitle;

  const _DocumentMetaSheet({
    required this.initialTitle,
  });

  @override
  State<_DocumentMetaSheet> createState() => _DocumentMetaSheetState();
}

class _DocumentMetaSheetState extends State<_DocumentMetaSheet> {
  late final TextEditingController _titleController;
  String _category = 'Allgemein';

  static const _categories = [
    'Allgemein',
    'Dienstplan',
    'Elternbrief',
    'Einverständniserklärung',
    'Ausbildung',
    'Veranstaltung',
    'Sonstiges',
  ];

  @override
  void initState() {
    super.initState();

    final name = widget.initialTitle;
    final dot = name.lastIndexOf('.');

    _titleController = TextEditingController(
      text: dot > 0 ? name.substring(0, dot) : name,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _continue() {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Titel eingeben.')),
      );
      return;
    }

    Navigator.pop(
      context,
      _DocumentMeta(
        title: title,
        category: _category,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dokument hochladen',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Titel *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                labelText: 'Kategorie',
                border: OutlineInputBorder(),
              ),
              items: _categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _category = value);
                }
              },
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _continue,
                icon: const Icon(Icons.upload_file),
                label: const Text('Hochladen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
