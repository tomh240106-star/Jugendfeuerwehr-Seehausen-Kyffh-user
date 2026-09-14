import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'documents_screen.dart';
import 'events_screen.dart';
import 'members_screen.dart';
import 'messages_screen.dart';
import 'training_plans_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  int _unreadMessages = 0;
  int _newDocuments = 0;

  void _openTab(int index) {
    setState(() {
      _selectedIndex = index;
    });

    _refreshBadges();
  }

  @override
  void initState() {
    super.initState();
    _refreshBadges();
  }

  Future<void> _refreshBadges() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final unreadRows = await Supabase.instance.client
          .from('messages')
          .select('id')
          .neq('sender_id', user.id)
          .isFilter('read_at', null);

      final documentRows = await Supabase.instance.client
          .from('documents')
          .select('id');

      final prefs = await SharedPreferences.getInstance();
      final readIds = (
        prefs.getStringList('read_documents_${user.id}') ??
            const <String>[]
      ).toSet();

      final newDocs = documentRows.where(
        (row) => !readIds.contains(row['id']?.toString() ?? ''),
      ).length;

      if (!mounted) return;

      setState(() {
        _unreadMessages = unreadRows.length;
        _newDocuments = newDocs;
      });
    } catch (_) {
      // Badges are optional UI; app stays usable if refresh fails.
    }
  }

  Widget _badgeIcon(
    IconData icon,
    int count,
  ) {
    if (count <= 0) {
      return Icon(icon);
    }

    return Badge.count(
      count: count,
      child: Icon(icon),
    );
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _DashboardPage(
        onOpenTab: _openTab,
        unreadMessages: _unreadMessages,
        newDocuments: _newDocuments,
        onRefreshBadges: _refreshBadges,
      ),
      const EventsScreen(),
      const TrainingPlansScreen(),
      const MessagesScreen(),
      const DocumentsScreen(),
      const MembersScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jugendfeuerwehr Seehausen'),
        actions: [
          IconButton(
            tooltip: 'Abmelden',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _openTab,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Start',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Termine',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Ausbildung',
          ),
          NavigationDestination(
            icon: _badgeIcon(
              Icons.message_outlined,
              _unreadMessages,
            ),
            selectedIcon: _badgeIcon(
              Icons.message,
              _unreadMessages,
            ),
            label: 'Nachrichten',
          ),
          NavigationDestination(
            icon: _badgeIcon(
              Icons.folder_outlined,
              _newDocuments,
            ),
            selectedIcon: _badgeIcon(
              Icons.folder,
              _newDocuments,
            ),
            label: 'Dokumente',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Mitglieder',
          ),
        ],
      ),
    );
  }
}

class _DashboardPage extends StatefulWidget {
  final ValueChanged<int> onOpenTab;
  final int unreadMessages;
  final int newDocuments;
  final Future<void> Function() onRefreshBadges;

  const _DashboardPage({
    required this.onOpenTab,
    required this.unreadMessages,
    required this.newDocuments,
    required this.onRefreshBadges,
  });

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  String? _error;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _nextEvent;
  String? _attendanceStatus;
  Map<String, dynamic>? _latestMessage;
  Map<String, dynamic>? _latestDocument;
  Map<String, dynamic>? _trainingPlan;
  int _memberCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadDashboard(),
      widget.onRefreshBadges(),
    ]);
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Kein Benutzer angemeldet.');
      }

      final profile = await _supabase
          .from('profiles')
          .select('id,first_name,last_name,role')
          .eq('id', user.id)
          .maybeSingle();

      final nowIso = DateTime.now().toUtc().toIso8601String();

      final eventRows = await _supabase
          .from('events')
          .select(
            'id,title,event_type,starts_at,location,meeting_point',
          )
          .gte('starts_at', nowIso)
          .order('starts_at', ascending: true)
          .limit(1);

      Map<String, dynamic>? nextEvent;
      String? attendanceStatus;

      if (eventRows.isNotEmpty) {
        nextEvent = Map<String, dynamic>.from(eventRows.first);

        final attendance = await _supabase
            .from('event_attendance')
            .select('status')
            .eq('event_id', nextEvent['id'])
            .eq('user_id', user.id)
            .maybeSingle();

        attendanceStatus = attendance?['status']?.toString();
      }

      final messageRows = await _supabase
          .from('messages')
          .select('id,body,created_at,conversation_id')
          .order('created_at', ascending: false)
          .limit(1);

      final documentRows = await _supabase
          .from('documents')
          .select('id,title,category,file_name,created_at')
          .order('created_at', ascending: false)
          .limit(1);

      final today = DateTime.now();
      final todayText =
          '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';

      final planRows = await _supabase
          .from('training_plans')
          .select('id,title,description,valid_from,valid_until')
          .or('valid_until.is.null,valid_until.gte.$todayText')
          .order('valid_from', ascending: true)
          .limit(1);

      final isTrainer =
          profile?['role']?.toString().trim().toLowerCase() == 'ausbilder';

      int memberCount = 0;
      if (isTrainer) {
        final members = await _supabase
            .from('profiles')
            .select('id');
        memberCount = members.length;
      }

      if (!mounted) return;

      setState(() {
        _profile = profile == null
            ? null
            : Map<String, dynamic>.from(profile);
        _isTrainer = isTrainer;
        _nextEvent = nextEvent;
        _attendanceStatus = attendanceStatus;
        _latestMessage = messageRows.isEmpty
            ? null
            : Map<String, dynamic>.from(messageRows.first);
        _latestDocument = documentRows.isEmpty
            ? null
            : Map<String, dynamic>.from(documentRows.first);
        _trainingPlan = planRows.isEmpty
            ? null
            : Map<String, dynamic>.from(planRows.first);
        _memberCount = memberCount;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _firstName() {
    final name = _profile?['first_name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Willkommen' : 'Hallo $name';
  }

  String _formatDateTime(dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (dt == null) return 'Datum unbekannt';

    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year} · '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')} Uhr';
  }

  String _formatDate(dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '');
    if (dt == null) return '–';

    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year}';
  }

  String _attendanceLabel(String? status) {
    switch (status) {
      case 'zugesagt':
        return 'Du nimmst teil';
      case 'abgesagt':
        return 'Du nimmst nicht teil';
      case 'entschuldigt':
        return 'Du bist entschuldigt';
      case 'offen':
        return 'Teilnahme noch offen';
      default:
        return 'Noch keine Rückmeldung';
    }
  }

  String _eventSubtitle() {
    final event = _nextEvent;
    if (event == null) return 'Aktuell ist kein zukünftiger Termin eingetragen.';

    final location = event['location']?.toString().trim() ?? '';
    final parts = <String>[
      _formatDateTime(event['starts_at']),
      _attendanceLabel(_attendanceStatus),
      if (location.isNotEmpty) location,
    ];

    return parts.join('\n');
  }

  String _messageSubtitle() {
    final message = _latestMessage;
    if (message == null) return 'Noch keine Nachricht vorhanden.';

    final body = message['body']?.toString().trim() ?? '';
    final text = body.isEmpty ? 'Neue Nachricht' : body;

    return '$text\n${_formatDateTime(message['created_at'])}';
  }

  String _documentSubtitle() {
    final doc = _latestDocument;
    if (doc == null) return 'Noch kein Dokument vorhanden.';

    final category = doc['category']?.toString().trim() ?? 'Allgemein';
    return '$category\n${_formatDateTime(doc['created_at'])}';
  }

  String _trainingSubtitle() {
    final plan = _trainingPlan;
    if (plan == null) return 'Aktuell ist kein Ausbildungsplan hinterlegt.';

    return 'Gültig: ${_formatDate(plan['valid_from'])} – '
        '${_formatDate(plan['valid_until'])}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 100),
            const Icon(
              Icons.error_outline,
              size: 70,
              color: Color(0xFFE30613),
            ),
            const SizedBox(height: 16),
            Text(
              'Startseite konnte nicht geladen werden.\n\n$_error',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            _firstName(),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF102638),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isTrainer
                ? 'Ausbilder · Jugendfeuerwehr Seehausen/Kyffhäuser'
                : 'Jugendfeuerwehr Seehausen/Kyffhäuser',
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 22),

          if (_nextEvent != null)
            _DashboardCard(
              icon: Icons.calendar_month,
              title: _nextEvent!['title']?.toString() ?? 'Nächster Termin',
              subtitle: _eventSubtitle(),
              onTap: () => widget.onOpenTab(1),
            )
          else
            _DashboardCard(
              icon: Icons.calendar_month,
              title: 'Nächster Termin',
              subtitle: _eventSubtitle(),
              onTap: () => widget.onOpenTab(1),
            ),

          const SizedBox(height: 12),

          _DashboardCard(
            icon: Icons.school,
            title: _trainingPlan?['title']?.toString() ?? 'Ausbildung',
            subtitle: _trainingSubtitle(),
            onTap: () => widget.onOpenTab(2),
          ),

          const SizedBox(height: 12),

          _DashboardCard(
            icon: Icons.message,
            title: widget.unreadMessages > 0
                ? 'Nachrichten · ${widget.unreadMessages} ungelesen'
                : 'Letzte Nachricht',
            subtitle: _messageSubtitle(),
            onTap: () => widget.onOpenTab(3),
          ),

          const SizedBox(height: 12),

          _DashboardCard(
            icon: Icons.folder,
            title: widget.newDocuments > 0
                ? 'Dokumente · ${widget.newDocuments} neu'
                : (_latestDocument?['title']?.toString() ?? 'Dokumente'),
            subtitle: _documentSubtitle(),
            onTap: () => widget.onOpenTab(4),
          ),

          if (_isTrainer) ...[
            const SizedBox(height: 12),
            _DashboardCard(
              icon: Icons.people,
              title: 'Mitglieder',
              subtitle: '$_memberCount Profile verwalten',
              onTap: () => widget.onOpenTab(5),
            ),
          ],

          const SizedBox(height: 24),

          const Text(
            'Schnellzugriff',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: Color(0xFF102638),
            ),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _QuickAction(
                icon: Icons.calendar_month,
                label: 'Termine',
                onTap: () => widget.onOpenTab(1),
              ),
              _QuickAction(
                icon: Icons.school,
                label: 'Ausbildung',
                onTap: () => widget.onOpenTab(2),
              ),
              _QuickAction(
                icon: Icons.message,
                label: 'Nachrichten',
                onTap: () => widget.onOpenTab(3),
              ),
              _QuickAction(
                icon: Icons.folder,
                label: 'Dokumente',
                onTap: () => widget.onOpenTab(4),
              ),
              if (_isTrainer)
                _QuickAction(
                  icon: Icons.people,
                  label: 'Mitglieder',
                  onTap: () => widget.onOpenTab(5),
                ),
            ],
          ),

          const SizedBox(height: 26),

          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Column(
                children: [
                  Icon(
                    Icons.local_fire_department,
                    size: 50,
                    color: Color(0xFFE30613),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Gemeinsam. Stark. Für morgen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE30613),
                foregroundColor: Colors.white,
                child: Icon(icon),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(
        icon,
        size: 19,
        color: const Color(0xFFE30613),
      ),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
