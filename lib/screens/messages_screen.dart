import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  String? _error;
  List<Map<String, dynamic>> _conversations = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await _loadRole();
    await _loadConversations();
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

  Future<void> _loadConversations() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final rows = await _supabase
          .from('conversations')
          .select()
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _conversations = List<Map<String, dynamic>>.from(rows);
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

  String _scopeLabel(dynamic scope) {
    switch (scope?.toString()) {
      case 'alle':
        return 'Alle';
      case 'gruppe':
        return 'Gruppe';
      default:
        return 'Einzelperson';
    }
  }

  Future<void> _createConversation() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _NewConversationSheet(),
    );

    if (created == true) {
      await _loadConversations();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _loadConversations,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            const Icon(Icons.error_outline, size: 70),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Nachrichten konnten nicht geladen werden.\n\n$_error',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadConversations,
        child: _conversations.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 100),
                  Icon(
                    Icons.forum_outlined,
                    size: 90,
                    color: Color(0xFFE30613),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Noch keine Unterhaltungen vorhanden.',
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
                itemCount: _conversations.length,
                itemBuilder: (context, index) {
                  final conversation = _conversations[index];
                  final title =
                      conversation['title']?.toString().trim().isNotEmpty == true
                          ? conversation['title'].toString()
                          : 'Unterhaltung';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFE30613),
                        foregroundColor: Colors.white,
                        child: Icon(
                          conversation['scope'] == 'alle'
                              ? Icons.campaign
                              : conversation['scope'] == 'gruppe'
                                  ? Icons.groups
                                  : Icons.person,
                        ),
                      ),
                      title: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        _scopeLabel(conversation['scope']),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  conversation: conversation,
                                ),
                              ),
                            )
                            .then((_) => _loadConversations());
                      },
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: _isTrainer
          ? FloatingActionButton.extended(
              onPressed: _createConversation,
              backgroundColor: const Color(0xFFE30613),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_comment),
              label: const Text('Nachricht'),
            )
          : null,
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> conversation;

  const ChatScreen({
    super.key,
    required this.conversation,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final rows = await _supabase
          .from('messages')
          .select('id,conversation_id,sender_id,body,created_at,read_at')
          .eq('conversation_id', widget.conversation['id'])
          .order('created_at', ascending: true);

      final raw = List<Map<String, dynamic>>.from(rows);

      final senderIds = raw
          .map((m) => m['sender_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final profilesById = <String, Map<String, dynamic>>{};

      if (senderIds.isNotEmpty) {
        final profiles = await _supabase
            .from('profiles')
            .select('id,first_name,last_name,role')
            .inFilter('id', senderIds);

        for (final p in profiles) {
          profilesById[p['id'].toString()] =
              Map<String, dynamic>.from(p);
        }
      }

      for (final m in raw) {
        m['sender_profile'] = profilesById[m['sender_id']?.toString()];
      }

      if (!mounted) return;

      setState(() {
        _messages = raw;
        _loading = false;
        _error = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _senderName(Map<String, dynamic> message) {
    final profile = message['sender_profile'] as Map<String, dynamic>?;
    final first = profile?['first_name']?.toString().trim() ?? '';
    final last = profile?['last_name']?.toString().trim() ?? '';
    final name = '$first $last'.trim();

    if (name.isNotEmpty) return name;

    if (message['sender_id']?.toString() ==
        _supabase.auth.currentUser?.id) {
      return 'Ich';
    }

    return 'Mitglied';
  }

  String _time(dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (dt == null) return '';

    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    final user = _supabase.auth.currentUser;

    if (body.isEmpty || user == null || _sending) return;

    setState(() => _sending = true);

    try {
      await _supabase.from('messages').insert({
        'conversation_id': widget.conversation['id'],
        'sender_id': user.id,
        'body': body,
      });

      _messageController.clear();
      await _loadMessages();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nachricht konnte nicht gesendet werden: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.conversation['title']?.toString().trim().isNotEmpty == true
            ? widget.conversation['title'].toString()
            : 'Nachrichten';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Fehler beim Laden:\n$_error',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _messages.isEmpty
                        ? const Center(
                            child: Text('Noch keine Nachrichten.'),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadMessages,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(14),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                final mine =
                                    message['sender_id']?.toString() ==
                                        _supabase.auth.currentUser?.id;

                                return Align(
                                  alignment: mine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 310,
                                    ),
                                    margin:
                                        const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: mine
                                          ? const Color(0xFFE30613)
                                          : Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      boxShadow: const [
                                        BoxShadow(
                                          blurRadius: 4,
                                          color: Color(0x22000000),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _senderName(message),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: mine
                                                ? Colors.white70
                                                : const Color(0xFFE30613),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          message['body']?.toString() ?? '',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: mine
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          _time(message['created_at']),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: mine
                                                ? Colors.white70
                                                : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Nachricht schreiben …',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendMessage,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewConversationSheet extends StatefulWidget {
  const _NewConversationSheet();

  @override
  State<_NewConversationSheet> createState() =>
      _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  final _supabase = Supabase.instance.client;
  final _titleController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _scope = 'einzelperson';
  List<Map<String, dynamic>> _profiles = [];
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;

      final rows = await _supabase
          .from('profiles')
          .select('id,first_name,last_name,role')
          .order('last_name')
          .order('first_name');

      if (!mounted) return;

      setState(() {
        _profiles = List<Map<String, dynamic>>.from(rows)
            .where((p) => p['id']?.toString() != currentUserId)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mitglieder konnten nicht geladen werden: $e')),
      );
    }
  }

  String _name(Map<String, dynamic> p) {
    final first = p['first_name']?.toString().trim() ?? '';
    final last = p['last_name']?.toString().trim() ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Mitglied' : name;
  }

  String _roleLabel(dynamic role) {
    switch (role?.toString()) {
      case 'ausbilder':
        return 'Ausbilder';
      case 'eltern':
        return 'Eltern';
      case 'jugendmitglied':
        return 'Jugendmitglied';
      default:
        return role?.toString() ?? '';
    }
  }

  void _changeScope(String? value) {
    if (value == null) return;

    setState(() {
      _scope = value;
      _selectedIds.clear();

      if (_scope == 'alle') {
        _selectedIds.addAll(
          _profiles.map((p) => p['id'].toString()),
        );
      }
    });
  }

  Future<void> _save() async {
    final user = _supabase.auth.currentUser;
    if (user == null || _saving) return;

    if (_scope == 'einzelperson' && _selectedIds.length != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte genau eine Person auswählen.'),
        ),
      );
      return;
    }

    if (_scope == 'gruppe' && _selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte mindestens eine Person auswählen.'),
        ),
      );
      return;
    }

    if (_scope == 'alle') {
      _selectedIds
        ..clear()
        ..addAll(_profiles.map((p) => p['id'].toString()));
    }

    setState(() => _saving = true);

    try {
      final created = await _supabase
          .from('conversations')
          .insert({
            'title': _titleController.text.trim().isEmpty
                ? (_scope == 'alle'
                    ? 'Mitteilung an alle'
                    : _scope == 'gruppe'
                        ? 'Gruppennachricht'
                        : 'Nachricht')
                : _titleController.text.trim(),
            'scope': _scope,
            'created_by': user.id,
          })
          .select('id')
          .single();

      final conversationId = created['id'].toString();

      final memberIds = <String>{
        user.id,
        ..._selectedIds,
      };

      await _supabase.from('conversation_members').insert(
            memberIds
                .map(
                  (id) => {
                    'conversation_id': conversationId,
                    'user_id': id,
                  },
                )
                .toList(),
          );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unterhaltung konnte nicht erstellt werden: $e')),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
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
              'Neue Unterhaltung',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Titel',
                hintText: 'z. B. Dienst am Samstag',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _scope,
              decoration: const InputDecoration(
                labelText: 'Empfänger',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'einzelperson',
                  child: Text('Einzelperson'),
                ),
                DropdownMenuItem(
                  value: 'gruppe',
                  child: Text('Gruppe'),
                ),
                DropdownMenuItem(
                  value: 'alle',
                  child: Text('Alle'),
                ),
              ],
              onChanged: _changeScope,
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_scope == 'alle')
              Card(
                child: ListTile(
                  leading: const Icon(Icons.campaign),
                  title: const Text('Alle Mitglieder'),
                  subtitle: Text(
                    '${_profiles.length + 1} Empfänger inklusive dir',
                  ),
                ),
              )
            else ...[
              Text(
                _scope == 'einzelperson'
                    ? 'Person auswählen'
                    : 'Personen auswählen',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 330),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _profiles.length,
                  itemBuilder: (context, index) {
                    final p = _profiles[index];
                    final id = p['id'].toString();
                    final selected = _selectedIds.contains(id);

                    return CheckboxListTile(
                      value: selected,
                      title: Text(_name(p)),
                      subtitle: Text(_roleLabel(p['role'])),
                      onChanged: (value) {
                        setState(() {
                          if (_scope == 'einzelperson') {
                            _selectedIds.clear();
                          }

                          if (value == true) {
                            _selectedIds.add(id);
                          } else {
                            _selectedIds.remove(id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || _loading ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_comment),
                label: const Text('Unterhaltung erstellen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
