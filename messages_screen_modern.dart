import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/home_navigation.dart';

const _msgBg = Color(0xFF020B13);
const _msgPanel = Color(0xFF071421);
const _msgPanel2 = Color(0xFF0A1A29);
const _msgBlue = Color(0xFF00A8FF);
const _msgRed = Color(0xFFE30613);
const _msgMuted = Color(0xFF9FB0C0);

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
  final Map<String, int> _unreadByConversation = {};
  final Map<String, Map<String, dynamic>> _latestByConversation = {};

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
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Kein Benutzer angemeldet.');

      final rows = await _supabase
          .from('conversations')
          .select()
          .order('created_at', ascending: false);

      final conversations = List<Map<String, dynamic>>.from(rows);
      final unread = <String, int>{};
      final latest = <String, Map<String, dynamic>>{};

      final overviewRows =
          await _supabase.rpc('get_conversation_overview');

      for (final raw in (overviewRows as List<dynamic>)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final conversationId = row['conversation_id']?.toString();
        if (conversationId == null || conversationId.isEmpty) continue;

        final unreadValue = row['unread_count'];
        unread[conversationId] = unreadValue is num
            ? unreadValue.toInt()
            : int.tryParse(unreadValue?.toString() ?? '') ?? 0;

        final latestCreatedAt = row['latest_created_at']?.toString();
        if (latestCreatedAt != null && latestCreatedAt.isNotEmpty) {
          latest[conversationId] = {
            'conversation_id': conversationId,
            'body': row['latest_body'],
            'created_at': latestCreatedAt,
          };
        }
      }

      conversations.sort((a, b) {
        DateTime? sortDate(Map<String, dynamic> conversation) {
          final id = conversation['id']?.toString();
          final message = id == null ? null : latest[id];
          return DateTime.tryParse(
                message?['created_at']?.toString() ?? '',
              ) ??
              DateTime.tryParse(
                conversation['created_at']?.toString() ?? '',
              );
        }

        final aDate = sortDate(a);
        final bDate = sortDate(b);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _unreadByConversation
          ..clear()
          ..addAll(unread);
        _latestByConversation
          ..clear()
          ..addAll(latest);
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

  String _messagePreview(Map<String, dynamic>? message) {
    if (message == null) return 'Noch keine Nachrichten';
    final text =
        message['body']?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ??
            '';
    if (text.isEmpty) return 'Neue Nachricht';
    return text.length > 70 ? '${text.substring(0, 67)}...' : text;
  }

  String _scopeLabel(dynamic scope) {
    switch (scope?.toString()) {
      case 'alle':
        return 'Mitteilung an alle';
      case 'gruppe':
        return 'Gruppenunterhaltung';
      default:
        return 'Direkte Unterhaltung';
    }
  }

  IconData _scopeIcon(String? scope) {
    switch (scope) {
      case 'alle':
        return Icons.campaign_rounded;
      case 'gruppe':
        return Icons.groups_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  Color _scopeColor(String? scope) {
    switch (scope) {
      case 'alle':
        return _msgRed;
      case 'gruppe':
        return _msgBlue;
      default:
        return const Color(0xFF22C55E);
    }
  }

  Future<void> _createConversation() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewConversationSheet(),
    );
    if (created == true) await _loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ColoredBox(
        color: _msgBg,
        child: Center(
          child: CircularProgressIndicator(color: _msgBlue),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: _msgBg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: _msgRed,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Nachrichten konnten nicht geladen werden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _msgMuted),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _msgBlue,
                    ),
                    onPressed: _loadConversations,
                    icon: const Icon(Icons.refresh_rounded),
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
      backgroundColor: _msgBg,
      body: RefreshIndicator(
        color: _msgBlue,
        backgroundColor: _msgPanel,
        onRefresh: _loadConversations,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration: BoxDecoration(
                color: _msgPanel,
                border: Border(
                  bottom: BorderSide(
                    color: _msgBlue.withValues(alpha: 0.28),
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Zur Startseite',
                        onPressed: () => HomeNavigation.goHome(context),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF0C2133),
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: _msgBlue.withValues(alpha: 0.28),
                          ),
                        ),
                        icon: const Icon(Icons.home_rounded),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 46,
                        height: 46,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF051420),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _msgBlue.withValues(alpha: 0.46),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.asset(
                            'assets/branding/logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nachrichten',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Informationen & Austausch',
                              style: TextStyle(
                                color: _msgMuted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isTrainer)
                        IconButton(
                          tooltip: 'Neue Unterhaltung',
                          onPressed: _createConversation,
                          style: IconButton.styleFrom(
                            backgroundColor: _msgRed,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.add_comment_rounded),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
              child: _conversations.isEmpty
                  ? const _MessageEmptyState()
                  : Column(
                      children: _conversations.map((conversation) {
                        final title = conversation['title']
                                    ?.toString()
                                    .trim()
                                    .isNotEmpty ==
                                true
                            ? conversation['title'].toString()
                            : 'Unterhaltung';
                        final scope = conversation['scope']?.toString();
                        final id = conversation['id']?.toString() ?? '';
                        final unread = _unreadByConversation[id] ?? 0;
                        final latest = _latestByConversation[id];
                        final accent = _scopeColor(scope);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 11),
                          decoration: BoxDecoration(
                            color: _msgPanel,
                            borderRadius: BorderRadius.circular(21),
                            border: Border.all(
                              color: unread > 0
                                  ? accent.withValues(alpha: 0.60)
                                  : const Color(0xFF1C3448),
                            ),
                            boxShadow: [
                              if (unread > 0)
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.08),
                                  blurRadius: 18,
                                ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
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
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: accent.withValues(alpha: 0.25),
                                        ),
                                      ),
                                      child: Icon(
                                        _scopeIcon(scope),
                                        color: accent,
                                        size: 27,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
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
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 17,
                                                    fontWeight: unread > 0
                                                        ? FontWeight.w900
                                                        : FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              if (unread > 0)
                                                Container(
                                                  constraints:
                                                      const BoxConstraints(
                                                    minWidth: 26,
                                                    minHeight: 26,
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 7,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: _msgRed,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      999,
                                                    ),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    unread > 99
                                                        ? '99+'
                                                        : '$unread',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _scopeLabel(scope),
                                            style: TextStyle(
                                              color: accent,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            _messagePreview(latest),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: unread > 0
                                                  ? const Color(0xFFDCE8F2)
                                                  : _msgMuted,
                                              fontSize: 13,
                                              fontWeight: unread > 0
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Color(0xFF718497),
                                    ),
                                  ],
                                ),
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
          ? FloatingActionButton.extended(
              onPressed: _createConversation,
              backgroundColor: _msgRed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text(
                'Neu',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
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

  RealtimeChannel? _messagesChannel;
  Timer? _receiptTimer;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<Map<String, dynamic>> _messages = [];
  final Map<String, List<Map<String, dynamic>>> _readReceiptsByMessage = {};

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
    _receiptTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadReadReceipts(),
    );
  }

  void _subscribeToMessages() {
    final conversationId = widget.conversation['id']?.toString();
    if (conversationId == null || conversationId.isEmpty) return;

    _messagesChannel = _supabase
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (_) async => _loadMessages(),
        )
        .subscribe();
  }

  Future<void> _markMessagesRead() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _supabase.rpc(
        'mark_conversation_read',
        params: {'p_conversation_id': widget.conversation['id']},
      );
    } catch (error) {
      debugPrint(
        'Nachrichten konnten nicht als gelesen markiert werden: $error',
      );
    }
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

      for (final message in raw) {
        message['sender_profile'] =
            profilesById[message['sender_id']?.toString()];
      }

      if (!mounted) return;
      setState(() {
        _messages = raw;
        _loading = false;
        _error = null;
      });

      await _markMessagesRead();
      await _loadReadReceipts();

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
    if (message['sender_id']?.toString() == _supabase.auth.currentUser?.id) {
      return 'Ich';
    }
    return 'Mitglied';
  }

  String _clock(dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _dayLabel(dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (dt == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final difference = today.difference(day).inDays;

    if (difference == 0) return 'Heute';
    if (difference == 1) return 'Gestern';

    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  bool _showDayDivider(int index) {
    if (index == 0) return true;
    final current = DateTime.tryParse(
      _messages[index]['created_at']?.toString() ?? '',
    )?.toLocal();
    final previous = DateTime.tryParse(
      _messages[index - 1]['created_at']?.toString() ?? '',
    )?.toLocal();

    if (current == null || previous == null) return false;
    return current.year != previous.year ||
        current.month != previous.month ||
        current.day != previous.day;
  }

  bool _showSenderName(int index, bool mine) {
    if (mine || index == 0) return !mine;
    final current = _messages[index];
    final previous = _messages[index - 1];
    if (_showDayDivider(index)) return true;
    return current['sender_id']?.toString() !=
        previous['sender_id']?.toString();
  }

  Future<void> _loadReadReceipts() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final rows = await _supabase.rpc(
        'get_message_read_status',
        params: {'p_conversation_id': widget.conversation['id']},
      );

      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final raw in (rows as List<dynamic>)) {
        final receipt = Map<String, dynamic>.from(raw as Map);
        final messageId = receipt['message_id']?.toString();
        if (messageId == null || messageId.isEmpty) continue;
        grouped.putIfAbsent(messageId, () => []).add(receipt);
      }

      if (!mounted) return;
      setState(() {
        _readReceiptsByMessage
          ..clear()
          ..addAll(grouped);
      });
    } catch (error) {
      debugPrint('Lesebestätigungen konnten nicht geladen werden: $error');
    }
  }

  List<Map<String, dynamic>> _receiptsFor(
    Map<String, dynamic> message,
  ) {
    final id = message['id']?.toString() ?? '';
    return _readReceiptsByMessage[id] ?? const <Map<String, dynamic>>[];
  }

  String _recipientName(Map<String, dynamic> receipt) {
    final first = receipt['first_name']?.toString().trim() ?? '';
    final last = receipt['last_name']?.toString().trim() ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Mitglied' : name;
  }

  String _receiptSummary(Map<String, dynamic> message) {
    final receipts = _receiptsFor(message);
    if (receipts.isEmpty) return 'Gesendet';
    final readCount =
        receipts.where((receipt) => receipt['is_read'] == true).length;
    if (receipts.length == 1) {
      return readCount == 1 ? 'Gelesen' : 'Gesendet';
    }
    return 'Gelesen von $readCount/${receipts.length}';
  }

  IconData _receiptIcon(Map<String, dynamic> message) {
    final receipts = _receiptsFor(message);
    final anyRead = receipts.any((receipt) => receipt['is_read'] == true);
    return anyRead ? Icons.done_all_rounded : Icons.done_rounded;
  }

  Color _receiptIconColor(Map<String, dynamic> message) {
    final receipts = _receiptsFor(message);
    if (receipts.isEmpty) return Colors.white70;
    final allRead = receipts.every((receipt) => receipt['is_read'] == true);
    return allRead ? const Color(0xFFB7F7C7) : Colors.white70;
  }

  String _receiptDateTime(dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.${dt.year} · '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')} Uhr';
  }

  void _showReadReceipts(Map<String, dynamic> message) {
    final receipts = _receiptsFor(message);
    final readCount =
        receipts.where((receipt) => receipt['is_read'] == true).length;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _MessageSheet(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 16),
                const Text(
                  'Lesebestätigung',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  receipts.isEmpty
                      ? 'Für diese Nachricht sind noch keine Empfängerinformationen verfügbar.'
                      : '$readCount von ${receipts.length} Empfängern haben die Nachricht gelesen.',
                  style: const TextStyle(color: _msgMuted),
                ),
                const SizedBox(height: 16),
                if (receipts.isEmpty)
                  const _SimpleInfoCard(
                    icon: Icons.done_rounded,
                    title: 'Nachricht wurde gesendet.',
                  )
                else
                  ...receipts.map((receipt) {
                    final isRead = receipt['is_read'] == true;
                    final readAt = _receiptDateTime(receipt['read_at']);
                    final color = isRead
                        ? const Color(0xFF22C55E)
                        : const Color(0xFF8A95A5);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _msgPanel2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: color.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Icon(
                              isRead
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _recipientName(receipt),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isRead && readAt.isNotEmpty
                                      ? 'Gelesen am $readAt'
                                      : 'Noch nicht gelesen',
                                  style: const TextStyle(
                                    color: _msgMuted,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
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

      try {
        final conversationTitle =
            widget.conversation['title']?.toString().trim();
        await _supabase.functions.invoke(
          'send-push',
          body: {
            'title': conversationTitle == null || conversationTitle.isEmpty
                ? 'Neue Nachricht'
                : conversationTitle,
            'body': body.length > 120 ? '${body.substring(0, 117)}...' : body,
            'conversation_id': widget.conversation['id'],
          },
        );
      } catch (pushError) {
        debugPrint('Nachricht gespeichert, Push fehlgeschlagen: $pushError');
      }

      _messageController.clear();
      await _loadMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nachricht konnte nicht gesendet werden: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _receiptTimer?.cancel();
    final channel = _messagesChannel;
    if (channel != null) {
      _supabase.removeChannel(channel);
    }
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
      backgroundColor: _msgBg,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: _msgPanel,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const Text(
              'Jugendfeuerwehr Seehausen/Kyffhäuser',
              style: TextStyle(
                color: _msgMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Zur Startseite',
            onPressed: () => HomeNavigation.goHome(context),
            icon: const Icon(Icons.home_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _msgBlue),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Fehler beim Laden:\n$_error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _msgMuted),
                          ),
                        ),
                      )
                    : _messages.isEmpty
                        ? const Center(
                            child: _SimpleInfoCard(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: 'Noch keine Nachrichten.',
                            ),
                          )
                        : RefreshIndicator(
                            color: _msgBlue,
                            backgroundColor: _msgPanel,
                            onRefresh: _loadMessages,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                16,
                                14,
                                16,
                              ),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                final mine =
                                    message['sender_id']?.toString() ==
                                        _supabase.auth.currentUser?.id;
                                final showSender =
                                    _showSenderName(index, mine);
                                final showDay = _showDayDivider(index);

                                return Column(
                                  children: [
                                    if (showDay)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _msgPanel2,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color:
                                                    const Color(0xFF1C3448),
                                              ),
                                            ),
                                            child: Text(
                                              _dayLabel(
                                                message['created_at'],
                                              ),
                                              style: const TextStyle(
                                                color: _msgMuted,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    Align(
                                      alignment: mine
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Container(
                                        constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.sizeOf(context).width *
                                                  0.78,
                                        ),
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.fromLTRB(
                                          14,
                                          11,
                                          14,
                                          9,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: mine
                                              ? const LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end:
                                                      Alignment.bottomRight,
                                                  colors: [
                                                    Color(0xFF006AA8),
                                                    Color(0xFF0B4EA2),
                                                  ],
                                                )
                                              : null,
                                          color: mine ? null : _msgPanel,
                                          borderRadius: BorderRadius.only(
                                            topLeft:
                                                const Radius.circular(18),
                                            topRight:
                                                const Radius.circular(18),
                                            bottomLeft: Radius.circular(
                                              mine ? 18 : 4,
                                            ),
                                            bottomRight: Radius.circular(
                                              mine ? 4 : 18,
                                            ),
                                          ),
                                          border: mine
                                              ? Border.all(
                                                  color: _msgBlue.withValues(
                                                    alpha: 0.25,
                                                  ),
                                                )
                                              : Border.all(
                                                  color: const Color(
                                                    0xFF1C3448,
                                                  ),
                                                ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: _msgBlue.withValues(
                                                alpha: mine ? 0.06 : 0.02,
                                              ),
                                              blurRadius: 12,
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (showSender) ...[
                                              Text(
                                                _senderName(message),
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w900,
                                                  color: _msgBlue,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                            ],
                                            Text(
                                              message['body']?.toString() ?? '',
                                              style: const TextStyle(
                                                fontSize: 15.5,
                                                height: 1.35,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _clock(
                                                      message['created_at'],
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      color: mine
                                                          ? Colors.white70
                                                          : _msgMuted,
                                                    ),
                                                  ),
                                                  if (mine) ...[
                                                    const SizedBox(width: 5),
                                                    Tooltip(
                                                      message:
                                                          _receiptSummary(
                                                        message,
                                                      ),
                                                      child: InkWell(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(999),
                                                        onTap: () =>
                                                            _showReadReceipts(
                                                          message,
                                                        ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(2),
                                                          child: Icon(
                                                            _receiptIcon(
                                                              message,
                                                            ),
                                                            size: 15,
                                                            color:
                                                                _receiptIconColor(
                                                              message,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              decoration: BoxDecoration(
                color: _msgPanel,
                border: Border(
                  top: BorderSide(
                    color: _msgBlue.withValues(alpha: 0.18),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: !_sending,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 5,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Nachricht schreiben …',
                        hintStyle: const TextStyle(
                          color: Color(0xFF718497),
                        ),
                        filled: true,
                        fillColor: _msgPanel2,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: Color(0xFF1C3448),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: _msgBlue),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: _msgRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(14),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
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
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _scope = 'einzelperson';
  String _roleFilter = 'alle';
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
        SnackBar(
          content: Text('Mitglieder konnten nicht geladen werden: $e'),
        ),
      );
    }
  }

  String _name(Map<String, dynamic> profile) {
    final first = profile['first_name']?.toString().trim() ?? '';
    final last = profile['last_name']?.toString().trim() ?? '';
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

  List<Map<String, dynamic>> get _filteredProfiles {
    final query = _searchController.text.trim().toLowerCase();
    return _profiles.where((profile) {
      final role = profile['role']?.toString() ?? '';
      final name = _name(profile).toLowerCase();
      final matchesRole = _roleFilter == 'alle' || role == _roleFilter;
      final matchesSearch = query.isEmpty || name.contains(query);
      return matchesRole && matchesSearch;
    }).toList();
  }

  int _countRole(String role) {
    return _profiles
        .where((profile) => profile['role']?.toString() == role)
        .length;
  }

  void _selectRole(String role) {
    if (_scope != 'gruppe') return;
    final ids = _profiles
        .where((profile) => profile['role']?.toString() == role)
        .map((profile) => profile['id'].toString());
    setState(() {
      _selectedIds.addAll(ids);
      _roleFilter = role;
    });
  }

  void _selectVisible() {
    if (_scope != 'gruppe') return;
    setState(() {
      _selectedIds.addAll(
        _filteredProfiles.map((profile) => profile['id'].toString()),
      );
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
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
      final memberIds = <String>{user.id, ..._selectedIds};

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
        SnackBar(
          content: Text('Unterhaltung konnte nicht erstellt werden: $e'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: _msgMuted),
      hintStyle: const TextStyle(color: Color(0xFF718497)),
      prefixIcon: Icon(icon, color: _msgBlue),
      filled: true,
      fillColor: _msgPanel2,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF1C3448)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _msgBlue),
      ),
    );
  }

  Widget _roleChip(
    String value,
    String label,
  ) {
    final selected = _roleFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _roleFilter = value),
      backgroundColor: _msgPanel2,
      selectedColor: _msgBlue.withValues(alpha: 0.18),
      side: BorderSide(
        color: selected
            ? _msgBlue.withValues(alpha: 0.7)
            : const Color(0xFF1C3448),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : _msgMuted,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _MessageSheet(
      child: Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(
            primary: _msgBlue,
            surface: _msgPanel,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.of(context).viewInsets.bottom + 22,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 16),
              const Text(
                'Neue Unterhaltung',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Empfänger wählen und Unterhaltung erstellen.',
                style: TextStyle(color: _msgMuted),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration(
                  label: 'Titel',
                  icon: Icons.title_rounded,
                  hint: 'z. B. Dienst am Samstag',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _scope,
                dropdownColor: _msgPanel2,
                decoration: _fieldDecoration(
                  label: 'Empfänger',
                  icon: Icons.people_alt_rounded,
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
                const Center(
                  child: CircularProgressIndicator(color: _msgBlue),
                )
              else if (_scope == 'alle')
                _SimpleInfoCard(
                  icon: Icons.campaign_rounded,
                  title: 'Alle Mitglieder',
                  subtitle:
                      '${_profiles.length + 1} Empfänger inklusive dir',
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _scope == 'einzelperson'
                            ? 'Person auswählen'
                            : 'Personen auswählen',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (_scope == 'gruppe')
                      Text(
                        '${_selectedIds.length} ausgewählt',
                        style: const TextStyle(
                          color: _msgBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration(
                    label: 'Mitglied suchen',
                    icon: Icons.search_rounded,
                  ).copyWith(
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Suche löschen',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(
                              Icons.close_rounded,
                              color: _msgMuted,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _roleChip(
                        'alle',
                        'Alle (${_profiles.length})',
                      ),
                      const SizedBox(width: 8),
                      _roleChip(
                        'jugendmitglied',
                        'Jugend (${_countRole('jugendmitglied')})',
                      ),
                      const SizedBox(width: 8),
                      _roleChip(
                        'eltern',
                        'Eltern (${_countRole('eltern')})',
                      ),
                      const SizedBox(width: 8),
                      _roleChip(
                        'ausbilder',
                        'Ausbilder (${_countRole('ausbilder')})',
                      ),
                    ],
                  ),
                ),
                if (_scope == 'gruppe') ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      ActionChip(
                        avatar:
                            const Icon(Icons.groups_rounded, size: 18),
                        label: const Text('Jugend'),
                        onPressed: () => _selectRole('jugendmitglied'),
                      ),
                      ActionChip(
                        avatar: const Icon(
                          Icons.family_restroom_rounded,
                          size: 18,
                        ),
                        label: const Text('Eltern'),
                        onPressed: () => _selectRole('eltern'),
                      ),
                      ActionChip(
                        avatar: const Icon(
                          Icons.local_fire_department_rounded,
                          size: 18,
                        ),
                        label: const Text('Ausbilder'),
                        onPressed: () => _selectRole('ausbilder'),
                      ),
                      ActionChip(
                        avatar:
                            const Icon(Icons.done_all_rounded, size: 18),
                        label: const Text('Sichtbare'),
                        onPressed:
                            _filteredProfiles.isEmpty ? null : _selectVisible,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.clear_rounded, size: 18),
                        label: const Text('Leeren'),
                        onPressed:
                            _selectedIds.isEmpty ? null : _clearSelection,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                if (_filteredProfiles.isEmpty)
                  const _SimpleInfoCard(
                    icon: Icons.person_search_rounded,
                    title: 'Keine passenden Mitglieder gefunden.',
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 330),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredProfiles.length,
                      itemBuilder: (context, index) {
                        final profile = _filteredProfiles[index];
                        final id = profile['id'].toString();
                        final selected = _selectedIds.contains(id);
                        final name = _name(profile);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          decoration: BoxDecoration(
                            color: _msgPanel2,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: selected
                                  ? _msgBlue.withValues(alpha: 0.55)
                                  : const Color(0xFF1C3448),
                            ),
                          ),
                          child: CheckboxListTile(
                            value: selected,
                            activeColor: _msgBlue,
                            checkColor: Colors.white,
                            title: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              _roleLabel(profile['role']),
                              style: const TextStyle(color: _msgMuted),
                            ),
                            secondary: CircleAvatar(
                              backgroundColor:
                                  _msgBlue.withValues(alpha: 0.12),
                              child: Text(
                                name.trim().isEmpty
                                    ? '?'
                                    : name.trim()[0].toUpperCase(),
                                style: const TextStyle(
                                  color: _msgBlue,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
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
                          ),
                        );
                      },
                    ),
                  ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _msgBlue,
                  ),
                  onPressed: _saving || _loading ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_comment_rounded),
                  label: const Text(
                    'Unterhaltung erstellen',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageSheet extends StatelessWidget {
  final Widget child;

  const _MessageSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: _msgPanel,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: child,
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFF31485B),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _MessageEmptyState extends StatelessWidget {
  const _MessageEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 48,
      ),
      decoration: BoxDecoration(
        color: _msgPanel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1C3448)),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.forum_outlined,
            size: 60,
            color: _msgBlue,
          ),
          SizedBox(height: 14),
          Text(
            'Noch keine Unterhaltungen vorhanden.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Sobald eine Unterhaltung erstellt wurde, erscheint sie hier.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _msgMuted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _SimpleInfoCard({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _msgPanel2,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFF1C3448)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _msgBlue),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: _msgMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
