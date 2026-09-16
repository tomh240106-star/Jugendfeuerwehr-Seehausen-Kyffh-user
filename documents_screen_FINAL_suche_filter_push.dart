import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  Set<String> _readDocumentIds = {};
  String _searchQuery = '';
  String _categoryFilter = 'Alle';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadRole(),
      _loadReadDocuments(),
      _loadDocuments(),
    ]);
  }

  Future<void> _loadReadDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _supabase.auth.currentUser?.id ?? 'unknown';
    final ids = prefs.getStringList('read_documents_$userId') ?? const <String>[];

    if (!mounted) return;

    setState(() {
      _readDocumentIds = ids.toSet();
    });
  }

  Future<void> _markDocumentRead(String id) async {
    if (id.isEmpty) return;

    final userId = _supabase.auth.currentUser?.id ?? 'unknown';
    final prefs = await SharedPreferences.getInstance();

    _readDocumentIds.add(id);
    await prefs.setStringList(
      'read_documents_$userId',
      _readDocumentIds.toList(),
    );

    if (mounted) {
      setState(() {});
    }
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
    await _markDocumentRead(document['id']?.toString() ?? '');

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

      try {
        await _supabase.functions.invoke(
          'send-push',
          body: {
            'title': 'Dokument entfernt',
            'body': '${document['title'] ?? document['file_name'] ?? 'Dokument'} wurde gelöscht.',
          },
        );
      } catch (pushError) {
        debugPrint('Dokument gelöscht, Push fehlgeschlagen: $pushError');
      }

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


  List<Map<String, dynamic>> get _filteredDocuments {
    final query = _searchQuery.trim().toLowerCase();

    return _documents.where((document) {
      final title = document['title']?.toString().toLowerCase() ?? '';
      final fileName = document['file_name']?.toString().toLowerCase() ?? '';
      final category = document['category']?.toString() ?? 'Allgemein';

      final matchesQuery =
          query.isEmpty || title.contains(query) || fileName.contains(query);

      final matchesCategory =
          _categoryFilter == 'Alle' || category == _categoryFilter;

      return matchesQuery && matchesCategory;
    }).toList();
  }

  List<String> get _categories {
    final values = <String>{'Alle'};
    for (final document in _documents) {
      values.add(document['category']?.toString() ?? 'Allgemein');
    }
    final list = values.toList();
    list.sort((a, b) {
      if (a == 'Alle') return -1;
      if (b == 'Alle') return 1;
      return a.compareTo(b);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A1F44);
    const blue = Color(0xFF0B4EA2);
    const red = Color(0xFFE30613);
    const green = Color(0xFF13A05B);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F5F7),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 70,
                    color: red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Dokumente konnten nicht geladen werden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _loadDocuments,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Erneut versuchen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: RefreshIndicator(
        onRefresh: _loadDocuments,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [navy, blue],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Image.asset(
                          'assets/branding/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dokumente',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Wichtige Dateien jederzeit griffbereit',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isTrainer)
                        IconButton(
                          tooltip: 'Dokument hochladen',
                          onPressed: _uploading ? null : _uploadDocument,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: red,
                          ),
                          icon: _uploading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload_file),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
              child: Column(
                children: [
                  TextField(
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                    decoration: InputDecoration(
                      hintText: 'Dokument suchen',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        return ChoiceChip(
                          label: Text(category),
                          selected: _categoryFilter == category,
                          onSelected: (_) {
                            setState(() => _categoryFilter = category);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
              child: _documents.isEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 54,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0xFFE3E8EE),
                        ),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.folder_open,
                            size: 72,
                            color: blue,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Noch keine Dokumente vorhanden.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: navy,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _filteredDocuments.isEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 40,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFFE3E8EE),
                            ),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 60,
                                color: Color(0xFF0B4EA2),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Keine passenden Dokumente gefunden.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0A1F44),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                      children: _filteredDocuments.map((document) {
                        final title =
                            document['title']?.toString() ?? 'Dokument';
                        final fileName =
                            document['file_name']?.toString() ?? 'Datei';
                        final category =
                            document['category']?.toString() ?? 'Allgemein';
                        final isNew = !_readDocumentIds.contains(
                          document['id']?.toString() ?? '',
                        );

                        final lower = fileName.toLowerCase();
                        Color accent = blue;
                        if (lower.endsWith('.pdf')) {
                          accent = red;
                        } else if (lower.endsWith('.jpg') ||
                            lower.endsWith('.jpeg') ||
                            lower.endsWith('.png') ||
                            lower.endsWith('.webp')) {
                          accent = green;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFE3E8EE),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                blurRadius: 12,
                                offset: Offset(0, 4),
                                color: Color(0x0D000000),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () => _openDocument(document),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      _iconForFile(fileName),
                                      color: accent,
                                      size: 29,
                                    ),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                title,
                                                style: const TextStyle(
                                                  color: navy,
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            if (isNew)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: red,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: const Text(
                                                  'NEU',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          category,
                                          style: TextStyle(
                                            color: accent,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          fileName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF667085),
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          _formatDate(
                                            document['created_at'],
                                          ),
                                          style: const TextStyle(
                                            color: Color(0xFF98A2B3),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _isTrainer
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
                                                leading:
                                                    Icon(Icons.open_in_new),
                                                title: Text('Öffnen'),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: ListTile(
                                                leading: Icon(
                                                  Icons.delete_outline,
                                                ),
                                                title: Text('Löschen'),
                                              ),
                                            ),
                                          ],
                                        )
                                      : const Icon(
                                          Icons.chevron_right,
                                          color: Color(0xFF7E8996),
                                        ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isTrainer
          ? FloatingActionButton(
              onPressed: _uploading ? null : _uploadDocument,
              backgroundColor: red,
              foregroundColor: Colors.white,
              child: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_file),
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
