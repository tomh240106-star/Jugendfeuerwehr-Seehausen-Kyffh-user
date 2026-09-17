import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'alarm_screen.dart';
import 'documents_screen.dart';
import 'events_screen.dart';
import 'members_screen.dart';
import 'messages_screen.dart';
import 'training_plans_screen.dart';
import '../services/push_service.dart';

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
  StreamSubscription<String>? _pushOpenSubscription;

  @override
  void initState() {
    super.initState();
    _refreshBadges();

    _pushOpenSubscription = PushService.openEvents.listen(
      _handlePushDestination,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = PushService.consumePendingDestination();
      if (pending != null) {
        _handlePushDestination(pending);
      }
    });
  }

  @override
  void dispose() {
    _pushOpenSubscription?.cancel();
    super.dispose();
  }

  void _handlePushDestination(String destination) {
    if (!mounted) return;

    switch (destination) {
      case 'alarm':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AlarmScreen(
              openedFromPush: true,
            ),
          ),
        );
        break;
      case 'events':
      case 'termine':
        _openTab(1);
        break;
      case 'messages':
      case 'nachrichten':
        _openTab(2);
        break;
      case 'documents':
      case 'dokumente':
        _openTab(3);
        break;
    }
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
        onOpenAlarm: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AlarmScreen(),
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
  final VoidCallback onOpenAlarm;
  final int unreadMessages;
  final int newDocuments;
  final Future<void> Function() onRefreshBadges;

  const _ModernDashboard({
    required this.onOpenTermine,
    required this.onOpenAusbildung,
    required this.onOpenNachrichten,
    required this.onOpenDokumente,
    required this.onOpenMitglieder,
    required this.onOpenAlarm,
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
  Map<String, dynamic>? _activeAlarm;
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

      final role =
          profile?['role']?.toString().trim().toLowerCase() ?? '';
      final isTrainer = role == 'ausbilder';
      final canUseAlarm =
          role == 'ausbilder' || role == 'jugendmitglied';

      Map<String, dynamic>? activeAlarm;
      if (canUseAlarm) {
        final activeRows = await _supabase
            .from('alarms')
            .select('id,title,description,location,created_at,is_active')
            .eq('is_active', true)
            .order('created_at', ascending: false)
            .limit(1);

        if (activeRows.isNotEmpty) {
          activeAlarm =
              Map<String, dynamic>.from(activeRows.first);
        }
      }

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
        _activeAlarm = activeAlarm;
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

  bool get _canUseAlarm {
    final role = _profile?['role']?.toString();
    return role == 'ausbilder' || role == 'jugendmitglied';
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
                if (_canUseAlarm) ...[
                  _FeatureCard(
                    background: _activeAlarm != null
                        ? const Color(0xFFE30613)
                        : const Color(0xFFB3000C),
                    icon: _activeAlarm != null
                        ? Icons.notification_important
                        : Icons.notifications_active,
                    eyebrow: _activeAlarm != null
                        ? 'AKTIVER JUGENDFEUERWEHR-ALARM'
                        : 'JUGENDFEUERWEHR-ALARM',
                    title: _activeAlarm?['title']?.toString() ??
                        'Alarm & Rückmeldung',
                    subtitle: _activeAlarm != null
                        ? '${(_activeAlarm!['location'] ?? 'Treffpunkt siehe Alarm').toString()}\nJetzt Rückmeldung öffnen'
                        : (_isTrainer
                            ? 'Alarm auslösen und Rückmeldungen der Jugendmitglieder sehen.'
                            : 'Hier erscheinen aktive Alarme und deine Rückmeldung.'),
                    onTap: widget.onOpenAlarm,
                  ),
                  const SizedBox(height: 14),
                ],
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
                        onTap: _isTrainer
                            ? widget.onOpenMitglieder
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const _MyProfileScreen(),
                                  ),
                                );
                              },
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
                        tooltip: 'Abmelden',
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Abmelden?'),
                              content: const Text(
                                'Möchtest du dich wirklich aus der App abmelden?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('Abbrechen'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('Abmelden'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true) {
                            await Supabase.instance.client.auth.signOut();
                          }
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


class _MoreScreen extends StatefulWidget {
  const _MoreScreen();

  @override
  State<_MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<_MoreScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await _supabase
          .from('profiles')
          .select(
            'id,first_name,last_name,role,phone,notifications_enabled',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _profile = profile == null
            ? null
            : Map<String, dynamic>.from(profile);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _name() {
    final first = _profile?['first_name']?.toString().trim() ?? '';
    final last = _profile?['last_name']?.toString().trim() ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Mein Profil' : name;
  }

  bool get _canUseAlarm {
    final role = _profile?['role']?.toString();
    return role == 'ausbilder' || role == 'jugendmitglied';
  }

  String _roleLabel() {
    switch (_profile?['role']?.toString()) {
      case 'ausbilder':
        return 'Ausbilder';
      case 'eltern':
        return 'Eltern';
      case 'jugendmitglied':
        return 'Jugendmitglied';
      default:
        return 'Mitglied';
    }
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _MyProfileScreen(),
      ),
    );

    await _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_navy, _blue],
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
                            'Mehr',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Profil, Einstellungen & Informationen',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
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
                  child: _loading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : Row(
                          children: [
                            const CircleAvatar(
                              radius: 30,
                              backgroundColor: Color(0xFFFFE6E8),
                              child: Icon(
                                Icons.person,
                                color: _red,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _name(),
                                    style: const TextStyle(
                                      color: _navy,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _roleLabel(),
                                    style: const TextStyle(
                                      color: Color(0xFF667085),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _openProfile,
                              icon: const Icon(Icons.edit_outlined),
                              color: _blue,
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 18),

                _MoreSection(
                  title: 'Verwaltung',
                  children: [
                    if (_canUseAlarm)
                      _MoreTile(
                        icon: Icons.notifications_active_outlined,
                        title: 'Alarm',
                        subtitle: _profile?['role'] == 'ausbilder'
                            ? 'Alarm auslösen und Rückmeldungen sehen'
                            : 'Auf aktive Jugendfeuerwehr-Alarme antworten',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AlarmScreen(),
                            ),
                          );
                        },
                      ),
                    _MoreTile(
                      icon: Icons.person_outline,
                      title: 'Mein Profil',
                      subtitle: 'Persönliche Daten bearbeiten',
                      onTap: _openProfile,
                    ),
                    _MoreTile(
                      icon: Icons.school_outlined,
                      title: 'Ausbildungspläne',
                      subtitle: 'Pläne und Ausbildungseinheiten',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TrainingPlansScreen(),
                          ),
                        );
                      },
                    ),
                    _MoreTile(
                      icon: _profile?['notifications_enabled'] == false
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_active_outlined,
                      title: 'Benachrichtigungen',
                      subtitle: _profile?['notifications_enabled'] == false
                          ? 'Push-Benachrichtigungen sind ausgeschaltet'
                          : 'Push-Benachrichtigungen sind eingeschaltet',
                      onTap: _openProfile,
                    ),
                    if (_profile?['role'] == 'ausbilder')
                      _MoreTile(
                        icon: Icons.groups_outlined,
                        title: 'Mitgliederverwaltung',
                        subtitle: 'Profile und Eltern-Kind-Verknüpfungen',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MembersScreen(),
                            ),
                          );
                        },
                      ),
                  ],
                ),

                const SizedBox(height: 18),

                _MoreSection(
                  title: 'Informationen',
                  children: [
                    _MoreTile(
                      icon: Icons.info_outline,
                      title: 'Über die App',
                      subtitle: 'Version und Zweck der App',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const _InfoScreen(),
                          ),
                        );
                      },
                    ),
                    _MoreTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Datenschutz',
                      subtitle: 'Hinweise zur Datenverarbeitung',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const _LegalTextScreen(
                              title: 'Datenschutz',
                              icon: Icons.privacy_tip_outlined,
                              intro:
                                  'Hier werden die Datenschutzhinweise der Jugendfeuerwehr hinterlegt.',
                              sections: [
                                'Verantwortliche Stelle',
                                'Verarbeitete Daten',
                                'Zwecke der Verarbeitung',
                                'Speicherdauer',
                                'Rechte der betroffenen Personen',
                                'Kontakt',
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    _MoreTile(
                      icon: Icons.gavel_outlined,
                      title: 'Impressum',
                      subtitle: 'Anbieter- und Kontaktangaben',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const _LegalTextScreen(
                              title: 'Impressum',
                              icon: Icons.gavel_outlined,
                              intro:
                                  'Hier werden die rechtlich erforderlichen Anbieterangaben eingetragen.',
                              sections: [
                                'Träger / Organisation',
                                'Anschrift',
                                'Vertretungsberechtigte Person',
                                'Kontakt',
                                'Haftungshinweise',
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Abmelden?'),
                          content: const Text(
                            'Möchtest du dich wirklich aus der App abmelden?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Abbrechen'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('Abmelden'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await _supabase.auth.signOut();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(Icons.logout),
                    label: const Text(
                      'Abmelden',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

class _MoreSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _MoreSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: 4,
            bottom: 8,
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE3E8EE),
            ),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _MoreTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 5,
      ),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FB),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          icon,
          color: const Color(0xFF0B4EA2),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF0A1F44),
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(
                color: Color(0xFF667085),
              ),
            ),
      trailing: const Icon(
        Icons.chevron_right,
        color: Color(0xFF98A2B3),
      ),
      onTap: onTap,
    );
  }
}

class _MyProfileScreen extends StatefulWidget {
  const _MyProfileScreen();

  @override
  State<_MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<_MyProfileScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _red = Color(0xFFE30613);

  final _supabase = Supabase.instance.client;

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _notificationsEnabled = true;
  String _role = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final profile = await _supabase
        .from('profiles')
        .select(
          'first_name,last_name,phone,role,notifications_enabled',
        )
        .eq('id', user.id)
        .maybeSingle();

    if (!mounted) return;

    _firstName.text = profile?['first_name']?.toString() ?? '';
    _lastName.text = profile?['last_name']?.toString() ?? '';
    _phone.text = profile?['phone']?.toString() ?? '';

    setState(() {
      _role = profile?['role']?.toString() ?? '';
      _notificationsEnabled =
          profile?['notifications_enabled'] != false;
      _loading = false;
    });
  }

  String _roleLabel() {
    switch (_role) {
      case 'ausbilder':
        return 'Ausbilder';
      case 'eltern':
        return 'Eltern';
      case 'jugendmitglied':
        return 'Jugendmitglied';
      default:
        return 'Mitglied';
    }
  }

  Future<void> _save() async {
    final user = _supabase.auth.currentUser;
    if (user == null || _saving) return;

    if (_firstName.text.trim().isEmpty ||
        _lastName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte Vorname und Nachname eingeben.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _supabase
          .from('profiles')
          .update({
            'first_name': _firstName.text.trim(),
            'last_name': _lastName.text.trim(),
            'phone': _phone.text.trim().isEmpty
                ? null
                : _phone.text.trim(),
            'notifications_enabled': _notificationsEnabled,
          })
          .eq('id', user.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil gespeichert.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Speichern fehlgeschlagen: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: const Text('Mein Profil'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Center(
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 42,
                        backgroundColor: Color(0xFFFFE6E8),
                        child: Icon(
                          Icons.person,
                          size: 42,
                          color: _red,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _roleLabel(),
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _firstName,
                  decoration: const InputDecoration(
                    labelText: 'Vorname',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lastName,
                  decoration: const InputDecoration(
                    labelText: 'Nachname',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Push-Benachrichtigungen',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Benachrichtigungen für Termine, Nachrichten, Dokumente und Ausbildung',
                  ),
                  value: _notificationsEnabled,
                  onChanged: (value) {
                    setState(() {
                      _notificationsEnabled = value;
                    });
                  },
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Profil speichern'),
                ),
              ],
            ),
    );
  }
}

class _InfoScreen extends StatelessWidget {
  const _InfoScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: const Text('Über die App'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Center(
            child: Container(
              width: 120,
              height: 120,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Image.asset(
                'assets/branding/logo.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Jugendfeuerwehr Seehausen/Kyffhäuser',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF0A1F44),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Gemeinsam. Stark. Für morgen.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          const _InfoBox(
            title: 'Version',
            text: '1.0.0',
          ),
          const SizedBox(height: 10),
          const _InfoBox(
            title: 'Zweck',
            text:
                'Die App unterstützt Termine, Ausbildung, Kommunikation, Dokumente und die Organisation der Jugendfeuerwehr.',
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String title;
  final String text;

  const _InfoBox({
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE3E8EE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0A1F44),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF667085),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalTextScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String intro;
  final List<String> sections;

  const _LegalTextScreen({
    required this.title,
    required this.icon,
    required this.intro,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFE3E8EE),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 46,
                  color: const Color(0xFF0B4EA2),
                ),
                const SizedBox(height: 12),
                Text(
                  intro,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...sections.map(
            (section) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFE3E8EE),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.circle,
                    size: 8,
                    color: Color(0xFFE30613),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      section,
                      style: const TextStyle(
                        color: Color(0xFF0A1F44),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hinweis: Die konkreten rechtlichen Angaben müssen vor einer öffentlichen Veröffentlichung mit den tatsächlichen Daten der verantwortlichen Organisation ergänzt werden.',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
