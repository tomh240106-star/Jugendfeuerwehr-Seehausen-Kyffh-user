import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/app_service.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesState();
}

class _MessagesState extends State<MessagesScreen> {
  late Future<List<Map<String, dynamic>>> future;
  String? role;

  @override
  void initState() {
    super.initState();
    future = AppService.conversations();
    AppService.myProfile().then((p) {
      if (mounted) setState(() => role = p?.role);
    });
  }

  void refresh() => setState(() => future = AppService.conversations());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('💬 Nachrichten'),
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NewConversationScreen(role: role)),
              );
              refresh();
            },
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }

          final list = snapshot.data ?? [];
          if (list.isEmpty) return const Center(child: Text('Noch keine Unterhaltungen.'));

          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final x = list[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(x['title'] ?? 'Unterhaltung'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      id: x['id'],
                      title: x['title'] ?? 'Nachrichten',
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class NewConversationScreen extends StatefulWidget {
  final String? role;
  const NewConversationScreen({super.key, this.role});

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  final title = TextEditingController();
  final selected = <String>{};
  bool loading = true;
  List<Profile> people = [];

  @override
  void initState() {
    super.initState();
    AppService.allProfiles().then((p) {
      if (mounted) {
        setState(() {
          people = p;
          loading = false;
        });
      }
    });
  }

  Future<void> create() async {
    if (selected.isEmpty || title.text.trim().isEmpty) return;

    await AppService.createConversation(
      memberIds: selected.toList(),
      title: title.text.trim(),
      scope: selected.length > 1 ? 'gruppe' : 'einzelperson',
    );

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Neue Nachricht')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Betreff / Titel'),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Empfänger',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...people.map(
                  (p) => CheckboxListTile(
                    value: selected.contains(p.id),
                    title: Text(p.name.isEmpty ? p.id : p.name),
                    subtitle: Text(p.role),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          selected.add(p.id);
                        } else {
                          selected.remove(p.id);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: create,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE30613)),
                  child: const Text('Unterhaltung erstellen'),
                ),
              ],
            ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String id;
  final String title;

  const ChatScreen({
    super.key,
    required this.id,
    required this.title,
  });

  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  final input = TextEditingController();
  late Future<List<Map<String, dynamic>>> future;

  @override
  void initState() {
    super.initState();
    future = AppService.messages(widget.id);
  }

  Future<void> send() async {
    if (input.text.trim().isEmpty) return;

    await AppService.sendMessage(widget.id, input.text);
    input.clear();
    setState(() => future = AppService.messages(widget.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: snapshot.data!
                      .map(
                        (m) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(m['body'] ?? ''),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    decoration: const InputDecoration(hintText: 'Nachricht schreiben'),
                  ),
                ),
                IconButton(
                  onPressed: send,
                  icon: const Icon(Icons.send, color: Color(0xFFE30613)),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
