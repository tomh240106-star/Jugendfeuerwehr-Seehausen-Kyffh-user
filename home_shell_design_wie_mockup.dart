import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);
  static const _orange = Color(0xFFFF7A00);

  int _selectedIndex = 0;
  int _unreadMessages = 0;
  int _newDocuments = 0;

  @override
  void initState() {
    super.initState();
    _refreshBadges();
  }

  void _openTab(int index) {
    setState(() => _selectedIndex = index);
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
      final readIds = (prefs.getStringList('read_documents_${user.id}') ??
              const <String>[])
          .toSet();

      final newDocs = documentRows
          .where((row) => !readIds.contains(row['id']?.toString() ?? ''))
          .length;

      if (!mounted) return;

      setState(() {
        _unreadMessages = unreadRows.length;
        _newDocuments = newDocs;
      });
    } catch (_) {}
  }

  Widget _navIcon(IconData icon, int count) {
    if (count <= 0) return Icon(icon);

    return Badge.count(
      count: count,
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _ModernDashboard(
        onOpenTermine: () => _openTab(1),
        onOpenAusbildung: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const TrainingPlansScreen(),
            ),
          );
        },
        onOpenNachrichten: () => _openTab(2),
        onOpenDokumente: () => _openTab(3),
        onOpenMitglieder: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const MembersScreen(),
            ),
          );
        },
        unreadMessages: _unreadMessages,
        newDocuments: _newDocuments,
        onRefreshBadges: _refreshBadges,
      ),
      const EventsScreen(),
      const MessagesScreen(),
      const DocumentsScreen(),
      const _MoreScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        height: 74,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE7F0FB),
        selectedIndex: _selectedIndex,
        onDestinationSelected: _openTab,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Start',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Termine',
          ),
          NavigationDestination(
            icon: _navIcon(Icons.chat_bubble_outline, _unreadMessages),
            selectedIcon: _navIcon(Icons.chat_bubble, _unreadMessages),
            label: 'Nachrichten',
          ),
          NavigationDestination(
            icon: _navIcon(Icons.folder_outlined, _newDocuments),
            selectedIcon: _navIcon(Icons.folder, _newDocuments),
            label: 'Dokumente',
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu),
            selectedIcon: Icon(Icons.menu),
            label: 'Mehr',
          ),
        ],
      ),
    );
  }
}

class _ModernDashboard extends StatefulWidget {
  final VoidCallback onOpenTermine;
  final VoidCallback onOpenAusbildung;
  final VoidCallback onOpenNachrichten;
  final VoidCallback onOpenDokumente;
  final VoidCallback onOpenMitglieder;
  final int unreadMessages;
  final int newDocuments;
  final Future<void> Function() onRefreshBadges;

  const _ModernDashboard({
    required this.onOpenTermine,
    required this.onOpenAusbildung,
    required this.onOpenNachrichten,
    required this.onOpenDokumente,
    required this.onOpenMitglieder,
    required this.unreadMessages,
    required this.newDocuments,
    required this.onRefreshBadges,
  });

  @override
  State<_ModernDashboard> createState() => _ModernDashboardState();
}

class _ModernDashboardState extends State<_ModernDashboard> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);
  static const _orange = Color(0xFFFF7A00);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  String? _error;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _nextEvent;
  String? _attendanceStatus;
  Map<String, dynamic>? _trainingPlan;
  int _memberCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _load(),
      widget.onRefreshBadges(),
    ]);
  }

  Future<void> _load() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Kein Benutzer angemeldet.');

      final profile = await _supabase
          .from('profiles')
          .select('id,first_name,last_name,role')
          .eq('id', user.id)
          .maybeSingle();

      final eventRows = await _supabase
          .from('events')
          .select('id,title,starts_at,location')
          .gte('starts_at', DateTime.now().toUtc().toIso8601String())
          .order('starts_at')
          .limit(1);

      Map<String, dynamic>? nextEvent;
      String? attendance;

      if (eventRows.isNotEmpty) {
        nextEvent = Map<String, dynamic>.from(eventRows.first);

        final row = await _supabase
            .from('event_attendance')
            .select('status')
            .eq('event_id', nextEvent['id'])
            .eq('user_id', user.id)
            .maybeSingle();

        attendance = row?['status']?.toString();
      }

      final today = DateTime.now();
      final todayText =
          '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';

      final plans = await _supabase
          .from('training_plans')
          .select('id,title,valid_from,valid_until')
          .or('valid_until.is.null,valid_until.gte.$todayText')
          .order('valid_from')
          .limit(1);

      final isTrainer =
          profile?['role']?.toString().trim().toLowerCase() == 'ausbilder';

      int memberCount = 0;
      if (isTrainer) {
        final rows = await _supabase.from('profiles').select('id');
        memberCount = rows.length;
      }

      if (!mounted) return;

      setState(() {
        _profile =
            profile == null ? null : Map<String, dynamic>.from(profile);
        _nextEvent = nextEvent;
        _attendanceStatus = attendance;
        _trainingPlan = plans.isEmpty
            ? null
            : Map<String, dynamic>.from(plans.first);
        _isTrainer = isTrainer;
        _memberCount = memberCount;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String get _firstName {
    final name = _profile?['first_name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Willkommen' : 'Hallo $name!';
  }

  String _eventDate(dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (dt == null) return 'Kein Datum';

    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year} · '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')} Uhr';
  }

  String _attendanceText() {
    switch (_attendanceStatus) {
      case 'zugesagt':
        return 'Ich nehme teil';
      case 'abgesagt':
        return 'Ich nehme nicht teil';
      case 'entschuldigt':
        return 'Entschuldigt';
      default:
        return 'Rückmeldung offen';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _HeroHeader(
            title: _firstName,
            subtitle: _isTrainer
                ? 'Ausbilder · Jugendfeuerwehr Seehausen/Kyffhäuser'
                : 'Jugendfeuerwehr Seehausen/Kyffhäuser',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            child: Column(
              children: [
                _FeatureCard(
                  background: _red,
                  icon: Icons.calendar_month,
                  eyebrow: 'NÄCHSTER TERMIN',
                  title: _nextEvent?['title']?.toString() ?? 'Kein Termin',
                  subtitle: _nextEvent == null
                      ? 'Aktuell ist kein zukünftiger Termin eingetragen.'
                      : '${_eventDate(_nextEvent!['starts_at'])}\n'
                          '${_nextEvent!['location'] ?? ''}\n'
                          '• ${_attendanceText()}',
                  onTap: widget.onOpenTermine,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _MiniFeature(
                        background: _blue,
                        icon: Icons.chat_bubble_outline,
                        value: widget.unreadMessages.toString(),
                        label: 'neue Nachrichten',
                        onTap: widget.onOpenNachrichten,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniFeature(
                        background: _green,
                        icon: Icons.folder_open,
                        value: widget.newDocuments.toString(),
                        label: 'neue Dokumente',
                        onTap: widget.onOpenDokumente,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _MiniFeature(
                        background: _orange,
                        icon: Icons.menu_book_outlined,
                        value: 'Plan',
                        label: _trainingPlan?['title']?.toString() ??
                            'Ausbildung',
                        onTap: widget.onOpenAusbildung,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniFeature(
                        background: Colors.white,
                        foreground: _navy,
                        icon: Icons.groups_outlined,
                        value: _isTrainer ? '$_memberCount' : 'Profil',
                        label: _isTrainer ? 'Mitglieder' : 'Mein Bereich',
                        onTap: widget.onOpenMitglieder,
                        bordered: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _SectionCard(
                  icon: Icons.local_fire_department,
                  title: 'Gemeinsam. Stark. Für morgen.',
                  subtitle:
                      'Jugendfeuerwehr Seehausen/Kyffhäuser',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _HeroHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A1F44),
            Color(0xFF0B4EA2),
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(34),
          bottomRight: Radius.circular(34),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -12,
                child: Opacity(
                  opacity: 0.10,
                  child: Icon(
                    Icons.local_fire_department,
                    size: 190,
                    color: Colors.white,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Image.asset(
                          'assets/branding/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Jugendfeuerwehr\nSeehausen/Kyffhäuser',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await Supabase.instance.client.auth.signOut();
                        },
                        icon: const Icon(
                          Icons.logout,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 31,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final Color background;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.background,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniFeature extends StatelessWidget {
  final Color background;
  final Color foreground;
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;
  final bool bordered;

  const _MiniFeature({
    required this.background,
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
    this.foreground = Colors.white,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      elevation: bordered ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: bordered
            ? const BorderSide(color: Color(0xFFDCE3EA))
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foreground, size: 28),
              const SizedBox(height: 18),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.88),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFE4E9EE),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 25,
            backgroundColor: Color(0xFFFFE6E8),
            child: Icon(
              Icons.local_fire_department,
              color: Color(0xFFE30613),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: const Text('Mehr'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MoreTile(
            icon: Icons.school_outlined,
            title: 'Ausbildungspläne',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TrainingPlansScreen(),
                ),
              );
            },
          ),
          _MoreTile(
            icon: Icons.groups_outlined,
            title: 'Mitglieder',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MembersScreen(),
                ),
              );
            },
          ),
          const _MoreTile(
            icon: Icons.info_outline,
            title: 'Über die App',
          ),
          const _MoreTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Datenschutz',
          ),
          const _MoreTile(
            icon: Icons.gavel_outlined,
            title: 'Impressum',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Abmelden'),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  const _MoreTile({
    required this.icon,
    required this.title,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0B4EA2)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
