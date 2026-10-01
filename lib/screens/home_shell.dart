import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/home_navigation.dart';
import '../services/push_service.dart';
import 'alarm_screen.dart';
import 'bug_report_screen.dart';
import 'documents_screen.dart';
import 'developer_console_screen.dart';
import 'events_screen.dart';
import 'legal_screen.dart';
import 'forms_pdf_screen.dart';
import 'material_management_screen.dart';
import 'member_records_screen.dart';
import 'members_screen.dart';
import 'messages_screen.dart';
import 'projects_screen.dart';
import 'training_plans_screen.dart';
import 'update_admin_screen.dart';
import 'user_bug_reports_admin_screen.dart';


class _HomeDashboardImages {
  static const String hero = 'assets/home/jugendfeuerwehr_am_hafen_bei_sonnenuntergang.png';
  static const String termine = 'assets/home/jugendfeuerwehr_am_hafen_im_sonnenuntergang.png';
  static const String ausbildung = 'assets/home/jugendfeuerwehr_plant_den_naechsten_einsatz.png';
  static const String nachrichten = 'assets/home/jugendfeuerwehr_im_goldenen_abendlicht.png';
  static const String dokumente = 'assets/home/jugendfeuerwehr_am_goldenen_hafen.png';
  static const String projekte = 'assets/home/feuerwehrteam_im_sonnenuntergang_am_hafen.png';
  static const String gemeinschaft = 'assets/home/feuerwehrjugend_am_hafen_im_sonnenuntergang.png';
  static const String banner = 'assets/home/jugendfeuerwehr_am_goldenen_meereshorizont.png';
}


class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  int _unreadMessages = 0;
  int _newDocuments = 0;
  StreamSubscription<String>? _pushOpenSubscription;

  @override
  void initState() {
    super.initState();

    HomeNavigation.register(_goHomeFromAnywhere);
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
    HomeNavigation.unregister();
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

      case 'projects':
      case 'projekte':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ProjectsScreen(),
          ),
        );
        break;
    }
  }

  void _goHomeFromAnywhere() {
    if (!mounted) return;

    setState(() => _selectedIndex = 0);
    _refreshBadges();
  }

  void _openTab(int index) {
    if (!mounted) return;

    setState(() => _selectedIndex = index);
    _refreshBadges();
  }

  Future<void> _refreshBadges() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final unreadResult = await Supabase.instance.client.rpc(
        'get_unread_message_count',
      );

      final unreadMessages = unreadResult is num
          ? unreadResult.toInt()
          : int.tryParse(unreadResult?.toString() ?? '') ?? 0;

      final documentRows =
          await Supabase.instance.client.from('documents').select('id');

      final prefs = await SharedPreferences.getInstance();

      final readIds =
          (prefs.getStringList('read_documents_${user.id}') ??
                  const <String>[])
              .toSet();

      final newDocuments = documentRows
          .where(
            (row) => !readIds.contains(row['id']?.toString() ?? ''),
          )
          .length;

      if (!mounted) return;

      setState(() {
        _unreadMessages = unreadMessages;
        _newDocuments = newDocuments;
      });
    } catch (_) {
      // Badges must never prevent the app from opening.
    }
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
        onOpenProjekte: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ProjectsScreen(),
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

    const navy = Color(0xFF06111F);
    const blue = Color(0xFF00A8FF);

    return Scaffold(
      backgroundColor: navy,
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 72,
          backgroundColor: const Color(0xFF071421),
          indicatorColor: blue.withValues(alpha: 0.16),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? blue
                  : const Color(0xFFB6C3D1),
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? blue
                  : const Color(0xFFB6C3D1),
            ),
          ),
        ),
        child: NavigationBar(
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
              icon: _navIcon(
                Icons.chat_bubble_outline,
                _unreadMessages,
              ),
              selectedIcon: _navIcon(
                Icons.chat_bubble,
                _unreadMessages,
              ),
              label: 'Nachrichten',
            ),
            NavigationDestination(
              icon: _navIcon(
                Icons.folder_outlined,
                _newDocuments,
              ),
              selectedIcon: _navIcon(
                Icons.folder,
                _newDocuments,
              ),
              label: 'Dokumente',
            ),
            const NavigationDestination(
              icon: Icon(Icons.menu),
              selectedIcon: Icon(Icons.menu),
              label: 'Mehr',
            ),
          ],
        ),
      ),
    );
  }
}

class _ModernDashboard extends StatefulWidget {
  final VoidCallback onOpenTermine;
  final VoidCallback onOpenAusbildung;
  final VoidCallback onOpenProjekte;
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
    required this.onOpenProjekte,
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
  int _upcomingEventCount = 0;
  int _openAttendanceCount = 0;
  int _openProjectCount = 0;
  int _openProjectTaskCount = 0;

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

      if (user == null) {
        throw Exception('Kein Benutzer angemeldet.');
      }

      final profile = await _supabase
          .from('profiles')
          .select('id,first_name,last_name,role')
          .eq('id', user.id)
          .maybeSingle();

      final role =
          profile?['role']?.toString().trim().toLowerCase() ?? '';

      final isTrainer = role == 'ausbilder';
      final canUseAlarm =
          role == 'ausbilder' || role == 'jugendmitglied';

      final eventRows = await _supabase
          .from('events')
          .select('id,title,starts_at,location')
          .gte(
            'starts_at',
            DateTime.now().toUtc().toIso8601String(),
          )
          .order('starts_at');

      Map<String, dynamic>? nextEvent;
      String? attendance;
      var openAttendanceCount = 0;

      if (eventRows.isNotEmpty) {
        nextEvent = Map<String, dynamic>.from(eventRows.first);

        if (role != 'eltern') {
          final eventIds = eventRows
              .map((event) => event['id']?.toString())
              .whereType<String>()
              .toList();

          final attendanceRows = eventIds.isEmpty
              ? const <Map<String, dynamic>>[]
              : List<Map<String, dynamic>>.from(
                  await _supabase
                      .from('event_attendance')
                      .select('event_id,status')
                      .eq('user_id', user.id)
                      .inFilter('event_id', eventIds),
                );

          final statusByEvent = <String, String>{};

          for (final row in attendanceRows) {
            final eventId = row['event_id']?.toString();
            final status = row['status']?.toString();

            if (eventId != null && status != null) {
              statusByEvent[eventId] = status;
            }
          }

          attendance =
              statusByEvent[nextEvent['id']?.toString()];

          for (final event in eventRows) {
            final eventId = event['id']?.toString();
            final status =
                eventId == null ? null : statusByEvent[eventId];

            if (status == null || status == 'offen') {
              openAttendanceCount++;
            }
          }
        }
      }

      final now = DateTime.now();

      final todayText =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final plans = await _supabase
          .from('training_plans')
          .select('id,title,valid_from,valid_until')
          .or('valid_until.is.null,valid_until.gte.$todayText')
          .order('valid_from')
          .limit(1);

      Map<String, dynamic>? activeAlarm;

      if (canUseAlarm) {
        final activeRows = await _supabase
            .from('alarms')
            .select(
              'id,title,description,location,created_at,is_active',
            )
            .eq('is_active', true)
            .order('created_at', ascending: false)
            .limit(1);

        if (activeRows.isNotEmpty) {
          activeAlarm =
              Map<String, dynamic>.from(activeRows.first);
        }
      }

      var memberCount = 0;
      var openProjectCount = 0;
      var openProjectTaskCount = 0;

      if (isTrainer) {
        final members =
            await _supabase.from('profiles').select('id');

        memberCount = members.length;

        final projects = await _supabase
            .from('projects')
            .select('id,status');

        openProjectCount = projects
            .where(
              (row) =>
                  row['status']?.toString() != 'abgeschlossen',
            )
            .length;

        final tasks = await _supabase
            .from('project_tasks')
            .select('id,status');

        openProjectTaskCount = tasks
            .where(
              (row) => row['status']?.toString() != 'erledigt',
            )
            .length;
      }

      if (!mounted) return;

      setState(() {
        _profile = profile == null
            ? null
            : Map<String, dynamic>.from(profile);
        _nextEvent = nextEvent;
        _attendanceStatus = attendance;
        _trainingPlan = plans.isEmpty
            ? null
            : Map<String, dynamic>.from(plans.first);
        _activeAlarm = activeAlarm;

        _isTrainer = isTrainer;
        _memberCount = memberCount;
        _upcomingEventCount = eventRows.length;
        _openAttendanceCount = openAttendanceCount;
        _openProjectCount = openProjectCount;
        _openProjectTaskCount = openProjectTaskCount;

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

    return role == 'ausbilder' ||
        role == 'jugendmitglied';
  }

  String get _firstName {
    final name =
        _profile?['first_name']?.toString().trim() ?? '';
    final hour = DateTime.now().hour;

    final greeting = hour < 11
        ? 'Guten Morgen'
        : hour < 18
            ? 'Guten Tag'
            : 'Guten Abend';

    return name.isEmpty ? greeting : '$greeting, $name';
  }

  String _eventDate(dynamic value) {
    final dt =
        DateTime.tryParse(value?.toString() ?? '')?.toLocal();

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
      return const ColoredBox(
        color: Color(0xFF06111F),
        child: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF00A8FF),
          ),
        ),
      );
    }

    final notificationCount =
        widget.unreadMessages + widget.newDocuments;

    final firstStatValue = _isTrainer
        ? '$_memberCount'
        : '$_upcomingEventCount';
    final firstStatLabel = _isTrainer
        ? 'Mitglieder'
        : 'Termine';
    final firstStatIcon = _isTrainer
        ? Icons.groups_rounded
        : Icons.calendar_month_rounded;
    final firstStatTap = _isTrainer
        ? widget.onOpenMitglieder
        : widget.onOpenTermine;

    final secondStatValue = _isTrainer
        ? '$_upcomingEventCount'
        : '$_openAttendanceCount';
    final secondStatLabel = _isTrainer
        ? 'Termine'
        : 'Rückmeldungen';
    final secondStatIcon = _isTrainer
        ? Icons.calendar_month_rounded
        : Icons.how_to_reg_rounded;

    final thirdStatValue = _isTrainer
        ? '$_openProjectTaskCount'
        : '$notificationCount';
    final thirdStatLabel = _isTrainer
        ? 'Aufgaben'
        : 'Hinweise';
    final thirdStatIcon = _isTrainer
        ? Icons.task_alt_rounded
        : Icons.notifications_active_rounded;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _HomeDashboardImages.hero,
          fit: BoxFit.cover,
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF020B13).withValues(alpha: 0.56),
                const Color(0xFF020B13).withValues(alpha: 0.91),
                const Color(0xFF020B13).withValues(alpha: 0.99),
              ],
            ),
          ),
        ),
        RefreshIndicator(
          color: const Color(0xFF00A8FF),
          backgroundColor: const Color(0xFF071421),
          onRefresh: _refreshAll,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _HeroHeader(
                title: _firstName,
                subtitle:
                    'Schön, dass du da bist!\nGemeinsam lernen, helfen, stark sein.',
                notificationCount: notificationCount,
                onNotifications: notificationCount > 0
                    ? (widget.unreadMessages > 0
                        ? widget.onOpenNachrichten
                        : widget.onOpenDokumente)
                    : widget.onOpenNachrichten,
                onReportProblem: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BugReportScreen()),
                  );
                },
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF311118),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFF4D5A)
                            .withValues(alpha: 0.7),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFFFD8DC),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DashboardStat(
                            icon: firstStatIcon,
                            value: firstStatValue,
                            label: firstStatLabel,
                            onTap: firstStatTap,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: _DashboardStat(
                            icon: secondStatIcon,
                            value: secondStatValue,
                            label: secondStatLabel,
                            onTap: widget.onOpenTermine,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: _DashboardStat(
                            icon: thirdStatIcon,
                            value: thirdStatValue,
                            label: thirdStatLabel,
                            onTap: _isTrainer
                                ? widget.onOpenProjekte
                                : (notificationCount > 0
                                    ? (widget.unreadMessages > 0
                                        ? widget.onOpenNachrichten
                                        : widget.onOpenDokumente)
                                    : widget.onOpenNachrichten),
                            highlight: notificationCount > 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_canUseAlarm) ...[
                      _FeatureCard(
                        background: _activeAlarm != null
                            ? const Color(0xFF9B0612)
                            : const Color(0xFF341018),
                        icon: _activeAlarm != null
                            ? Icons.notification_important_rounded
                            : Icons.notifications_active_rounded,
                        eyebrow: _activeAlarm != null
                            ? 'AKTIVER ALARM'
                            : 'JUGENDFEUERWEHR-ALARM',
                        title: _activeAlarm?['title']?.toString() ??
                            'Alarm & Rückmeldung',
                        subtitle: _activeAlarm != null
                            ? '${(_activeAlarm!['location'] ?? 'Treffpunkt siehe Alarm').toString()}\nJetzt Rückmeldung öffnen'
                            : (_isTrainer
                                ? 'Alarm auslösen und Rückmeldungen ansehen.'
                                : 'Hier erscheinen aktive Alarme und deine Rückmeldung.'),
                        onTap: widget.onOpenAlarm,
                      ),
                      const SizedBox(height: 14),
                    ],
                    _FeatureCard(
                      background: const Color(0xFF081B2D),
                      icon: Icons.calendar_month_rounded,
                      eyebrow: 'NÄCHSTER TERMIN',
                      title: _nextEvent?['title']?.toString() ??
                          'Kein Termin geplant',
                      subtitle: _nextEvent == null
                          ? 'Aktuell ist kein zukünftiger Termin eingetragen.'
                          : (_profile?['role']?.toString() == 'eltern'
                              ? '${_eventDate(_nextEvent!['starts_at'])}\n${_nextEvent!['location'] ?? ''}'
                              : '${_eventDate(_nextEvent!['starts_at'])}\n${_nextEvent!['location'] ?? ''}\n${_attendanceText()}'),
                      onTap: widget.onOpenTermine,
                    ),
                    const SizedBox(height: 20),
                    const _DashboardSectionTitle(
                      title: 'Schnellzugriff',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniFeature(
                            background: const Color(0xFF0A1A29),
                            imagePath: _HomeDashboardImages.termine,
                            icon: Icons.calendar_month_rounded,
                            value: 'Termine',
                            label: 'Alle Termine im Überblick',
                            onTap: widget.onOpenTermine,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniFeature(
                            background: const Color(0xFF0A1A29),
                            imagePath: _HomeDashboardImages.ausbildung,
                            icon: Icons.menu_book_rounded,
                            value: 'Ausbildung',
                            label: _trainingPlan?['title']?.toString() ??
                                'Pläne, Themen & Inhalte',
                            onTap: widget.onOpenAusbildung,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniFeature(
                            background: const Color(0xFF0A1A29),
                            imagePath: _HomeDashboardImages.nachrichten,
                            icon: Icons.campaign_rounded,
                            value: 'Nachrichten',
                            label: widget.unreadMessages > 0
                                ? '${widget.unreadMessages} ungelesen'
                                : 'Aktuelle Infos',
                            onTap: widget.onOpenNachrichten,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniFeature(
                            background: const Color(0xFF0A1A29),
                            imagePath: _HomeDashboardImages.dokumente,
                            icon: Icons.folder_rounded,
                            value: 'Dokumente',
                            label: widget.newDocuments > 0
                                ? '${widget.newDocuments} neue Unterlagen'
                                : 'Wichtige Unterlagen',
                            onTap: widget.onOpenDokumente,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniFeature(
                            background: const Color(0xFF0A1A29),
                            imagePath: _HomeDashboardImages.projekte,
                            icon: Icons.account_tree_rounded,
                            value: _isTrainer ? 'Projekte' : 'Mein Bereich',
                            label: _isTrainer
                                ? '$_openProjectCount offen · $_openProjectTaskCount Aufgaben'
                                : 'Profil und persönliche Daten',
                            onTap: _isTrainer
                                ? widget.onOpenProjekte
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const _MyProfileScreen(),
                                      ),
                                    );
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniFeature(
                            background: const Color(0xFF0A1A29),
                            imagePath: _HomeDashboardImages.gemeinschaft,
                            icon: Icons.groups_rounded,
                            value: _isTrainer ? 'Mitglieder' : 'Gemeinschaft',
                            label: _isTrainer
                                ? '$_memberCount Mitglieder verwalten'
                                : 'Jugendfeuerwehr Seehausen/Kyffhäuser',
                            onTap: _isTrainer
                                ? widget.onOpenMitglieder
                                : widget.onOpenAusbildung,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _SectionCard(
                      icon: Icons.sailing_rounded,
                      title: 'Eine starke Gemeinschaft für morgen!',
                      subtitle: 'Jugendfeuerwehr Seehausen/Kyffhäuser',
                      backgroundImage: _HomeDashboardImages.banner,
                      thumbnailImage: _HomeDashboardImages.gemeinschaft,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int notificationCount;
  final VoidCallback onNotifications;
  final VoidCallback onReportProblem;

  const _HeroHeader({
    required this.title,
    required this.subtitle,
    required this.notificationCount,
    required this.onNotifications,
    required this.onReportProblem,
  });

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF00A8FF);
    const deepNavy = Color(0xFF03101D);

    return Container(
      height: 312,
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: blue.withValues(alpha: 0.72),
          width: 1.25,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: blue.withValues(alpha: 0.10),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _HomeDashboardImages.hero,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.42, 0.72, 1.0],
                colors: [
                  deepNavy.withValues(alpha: 0.12),
                  deepNavy.withValues(alpha: 0.24),
                  deepNavy.withValues(alpha: 0.64),
                  deepNavy.withValues(alpha: 0.95),
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06111F)
                              .withValues(alpha: 0.84),
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(
                            color: blue.withValues(alpha: 0.84),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: blue.withValues(alpha: 0.22),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.asset(
                            'assets/branding/logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Jugendfeuerwehr',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17.5,
                                height: 1.05,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.1,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Seehausen / Kyffhäuser',
                              style: TextStyle(
                                color: blue,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fehler melden',
                        onPressed: onReportProblem,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF06111F).withValues(alpha: 0.72),
                          side: BorderSide(color: blue.withValues(alpha: 0.42)),
                          minimumSize: const Size(46, 46),
                        ),
                        icon: const Icon(Icons.help_outline_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            tooltip: 'Benachrichtigungen',
                            onPressed: onNotifications,
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF06111F)
                                  .withValues(alpha: 0.72),
                              side: BorderSide(
                                color: blue.withValues(alpha: 0.42),
                              ),
                              minimumSize: const Size(46, 46),
                            ),
                            icon: const Icon(
                              Icons.notifications_none_rounded,
                              color: Colors.white,
                            ),
                          ),
                          if (notificationCount > 0)
                            Positioned(
                              right: -1,
                              top: -2,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE30613),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFF06111F),
                                    width: 2,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  notificationCount > 99
                                      ? '99+'
                                      : '$notificationCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFF04111D)
                          .withValues(alpha: 0.64),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.09),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 4,
                          height: 67,
                          decoration: BoxDecoration(
                            color: blue,
                            borderRadius: BorderRadius.circular(99),
                            boxShadow: [
                              BoxShadow(
                                color: blue.withValues(alpha: 0.42),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 27,
                                  height: 1.0,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 13.2,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
    const blue = Color(0xFF00A8FF);
    final isAlarm = eyebrow.contains('ALARM');
    final accent = isAlarm ? const Color(0xFFFF3948) : blue;

    return Material(
      color: background.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: accent.withValues(alpha: 0.72),
          width: 1.1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 13, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.38),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.12),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      eyebrow,
                      style: TextStyle(
                        color: accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18.5,
                        height: 1.12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFD4DFE9),
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  const _DashboardStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF00A8FF);
    final accent = highlight ? const Color(0xFFFF3948) : blue;

    return Material(
      color: const Color(0xFF071624).withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: accent.withValues(alpha: 0.52),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 13,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.07),
                Colors.transparent,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: accent, size: 21),
              ),
              const SizedBox(height: 7),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFB8C5D2),
                  fontSize: 10.2,
                  fontWeight: FontWeight.w700,
                ),
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
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;
  final String? imagePath;

  const _MiniFeature({
    required this.background,
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF00A8FF);

    return Material(
      color: background.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: blue.withValues(alpha: 0.52),
          width: 1.05,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 142,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imagePath != null)
                Image.asset(
                  imagePath!,
                  fit: BoxFit.cover,
                ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.42, 1.0],
                    colors: [
                      const Color(0xFF04111D).withValues(alpha: 0.18),
                      const Color(0xFF04111D).withValues(alpha: 0.30),
                      const Color(0xFF04111D).withValues(alpha: 0.95),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        blue.withValues(alpha: 0.72),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 39,
                          height: 39,
                          decoration: BoxDecoration(
                            color: const Color(0xFF04111D)
                                .withValues(alpha: 0.68),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: blue.withValues(alpha: 0.46),
                            ),
                          ),
                          child: Icon(
                            icon,
                            color: Colors.white,
                            size: 21,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: const Color(0xFF04111D)
                                .withValues(alpha: 0.58),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.09),
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(
                            blurRadius: 8,
                            color: Colors.black87,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontSize: 11,
                        height: 1.22,
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(
                            blurRadius: 6,
                            color: Colors.black87,
                          ),
                        ],
                      ),
                    ),
                  ],
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
  final String? backgroundImage;
  final String? thumbnailImage;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.backgroundImage,
    this.thumbnailImage,
  });

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF00A8FF);

    return Container(
      width: double.infinity,
      height: 138,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: blue.withValues(alpha: 0.58),
          width: 1.05,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
          BoxShadow(
            color: blue.withValues(alpha: 0.08),
            blurRadius: 18,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            backgroundImage ?? _HomeDashboardImages.banner,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0.0, 0.58, 1.0],
                colors: [
                  const Color(0xFF03101D).withValues(alpha: 0.96),
                  const Color(0xFF03101D).withValues(alpha: 0.70),
                  const Color(0xFF03101D).withValues(alpha: 0.46),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 10,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF03101D).withValues(alpha: 0.30),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 25,
                color: Colors.white.withValues(alpha: 0.20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 82,
                  height: 82,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06111F)
                        .withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(
                      color: blue.withValues(alpha: 0.62),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: blue.withValues(alpha: 0.12),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(19),
                    child: Image.asset(
                      thumbnailImage ?? 'assets/branding/logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17.5,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: blue.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: blue,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
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

class _DashboardSectionTitle extends StatelessWidget {
  final String title;

  const _DashboardSectionTitle({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 25,
          decoration: BoxDecoration(
            color: const Color(0xFF00A8FF),
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00A8FF).withValues(alpha: 0.30),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            height: 1.0,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.15,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00A8FF).withValues(alpha: 0.30),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
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
  bool _isDeveloper = false;
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
      final result = await Future.wait([
        _supabase
            .from('profiles')
            .select(
              'id,first_name,last_name,role,phone,notifications_enabled',
            )
            .eq('id', user.id)
            .maybeSingle(),
        _supabase
            .from('developer_access')
            .select('user_id')
            .eq('user_id', user.id)
            .maybeSingle(),
      ]);

      final profile = result[0];
      final developerAccess = result[1];

      if (!mounted) return;

      setState(() {
        _profile = profile == null
            ? null
            : Map<String, dynamic>.from(profile);
        _isDeveloper = developerAccess != null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isDeveloper = false;
        _loading = false;
      });
    }
  }

  String _name() {
    final first =
        _profile?['first_name']?.toString().trim() ?? '';
    final last =
        _profile?['last_name']?.toString().trim() ?? '';

    final name = '$first $last'.trim();

    return name.isEmpty ? 'Mein Profil' : name;
  }

  bool get _canUseAlarm {
    final role = _profile?['role']?.toString();

    return role == 'ausbilder' ||
        role == 'jugendmitglied';
  }

  bool get _isTrainer {
    return _profile?['role']?.toString() ==
        'ausbilder';
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
      backgroundColor: const Color(0xFF06111F),
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
                padding: const EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  24,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Zur Startseite',
                      onPressed: () =>
                          HomeNavigation.goHome(
                        context,
                      ),
                      style:
                          IconButton.styleFrom(
                        backgroundColor:
                            Colors.white,
                        foregroundColor: _navy,
                      ),
                      icon: const Icon(
                        Icons.home_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 48,
                      height: 48,
                      padding:
                          const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                      child: Image.asset(
                        'assets/branding/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            'Mehr',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight:
                                  FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Profil, Einstellungen & Informationen',
                            style: TextStyle(
                              color:
                                  Colors.white70,
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
            padding:
                const EdgeInsets.fromLTRB(16, 18, 16, 100),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(22),
                    border: Border.all(
                      color:
                          const Color(0xFFE3E8EE),
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
                            padding:
                                EdgeInsets.all(18),
                            child:
                                CircularProgressIndicator(),
                          ),
                        )
                      : Row(
                          children: [
                            const CircleAvatar(
                              radius: 30,
                              backgroundColor:
                                  Color(0xFFFFE6E8),
                              child: Icon(
                                Icons.person,
                                color: _red,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Text(
                                    _name(),
                                    style:
                                        const TextStyle(
                                      color: _navy,
                                      fontSize: 19,
                                      fontWeight:
                                          FontWeight
                                              .w800,
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 3,
                                  ),
                                  Text(
                                    _roleLabel(),
                                    style:
                                        const TextStyle(
                                      color: Color(
                                        0xFF667085,
                                      ),
                                      fontWeight:
                                          FontWeight
                                              .w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _openProfile,
                              icon: const Icon(
                                Icons.edit_outlined,
                              ),
                              color: _blue,
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                _MoreSection(
                  title: 'Mein Bereich',
                  children: [
                    _MoreTile(
                      icon: Icons.person_outline,
                      title: 'Mein Profil',
                      subtitle:
                          'Persönliche Daten und Einstellungen',
                      onTap: _openProfile,
                    ),
                    if (_profile?['role'] ==
                        'eltern')
                      _MoreTile(
                        icon:
                            Icons.family_restroom,
                        title: 'Meine Kinder',
                        subtitle:
                            'Verknüpfte Jugendmitglieder und Termine',
                        onTap: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const _ParentAreaScreen(),
                            ),
                          );
                        },
                      ),
                    _MoreTile(
                      icon: _profile?[
                                  'notifications_enabled'] ==
                              false
                          ? Icons
                              .notifications_off_outlined
                          : Icons
                              .notifications_active_outlined,
                      title: 'Benachrichtigungen',
                      subtitle: _profile?[
                                  'notifications_enabled'] ==
                              false
                          ? 'Push-Benachrichtigungen sind ausgeschaltet'
                          : 'Push-Benachrichtigungen sind eingeschaltet',
                      onTap: _openProfile,
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                if (_isTrainer) ...[
                  _MoreSection(
                    title: 'Ausbilderbereich',
                    children: [
                      _MoreTile(
                        icon: Icons
                            .account_tree_outlined,
                        title: 'Projekte',
                        subtitle:
                            'Projekte planen, Aufgaben verteilen und Fortschritt verfolgen',
                        onTap: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const ProjectsScreen(),
                            ),
                          );
                        },
                      ),
                      _MoreTile(
                        icon: Icons.groups_outlined,
                        title:
                            'Mitgliederverwaltung',
                        subtitle:
                            'Profile und Eltern-Kind-Verknüpfungen',
                        onTap: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const MembersScreen(),
                            ),
                          );
                        },
                      ),
                      _MoreTile(
                        icon: Icons.badge_outlined,
                        title: 'Stammblätter',
                        subtitle:
                            'Interne Daten der Jugendmitglieder',
                        onTap: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const MemberRecordsScreen(),
                            ),
                          );
                        },
                      ),
                      _MoreTile(
                        icon: Icons.inventory_2_outlined,
                        title: 'Materialverwaltung',
                        subtitle:
                            'Bestände, Ausgaben, Rückgaben und Defekte',
                        onTap: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const MaterialManagementScreen(),
                            ),
                          );
                        },
                      ),
                      _MoreTile(
                        icon: Icons.picture_as_pdf_outlined,
                        title: 'Formulare & PDF',
                        subtitle:
                            'Ausbildungsnachweise, Materialausgabe und Stammdatenblätter',
                        onTap: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const FormsPdfScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],

                if (_isDeveloper) ...[
                  _MoreSection(
                    title: 'Entwickler',
                    children: [
                      _MoreTile(
                        icon: Icons.developer_mode_outlined,
                        title: 'Entwicklerkonsole',
                        subtitle:
                            'Fehlerprotokolle und technische Diagnose',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const DeveloperConsoleScreen(),
                            ),
                          );
                        },
                      ),
                      _MoreTile(
                        icon: Icons.bug_report_outlined,
                        title: 'Fehlermeldungen',
                        subtitle: 'Meldungen der Nutzer verwalten und bearbeiten',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const UserBugReportsAdminScreen(),
                            ),
                          );
                        },
                      ),
                      _MoreTile(
                        icon: Icons.system_update_alt,
                        title: 'Update-Server',
                        subtitle:
                            'NON, BETA, FOR ALL und Beta-Nutzer verwalten',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const UpdateAdminScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],

                _MoreSection(
                  title: 'Jugendfeuerwehr',
                  children: [
                    if (_canUseAlarm)
                      _MoreTile(
                        icon: Icons
                            .notifications_active_outlined,
                        title: 'Alarm',
                        subtitle: _isTrainer
                            ? 'Alarm auslösen und Rückmeldungen sehen'
                            : 'Auf aktive Jugendfeuerwehr-Alarme antworten',
                        onTap: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const AlarmScreen(),
                            ),
                          );
                        },
                      ),
                    _MoreTile(
                      icon: Icons.school_outlined,
                      title: 'Ausbildungspläne',
                      subtitle:
                          'Pläne und Ausbildungseinheiten',
                      onTap: () {
                        Navigator.of(context)
                            .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const TrainingPlansScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _MoreSection(
                  title:
                      'Informationen & Rechtliches',
                  children: [
                    _MoreTile(
                      icon: Icons.info_outline,
                      title: 'Über die App',
                      subtitle:
                          'Version und Zweck der App',
                      onTap: () {
                        Navigator.of(context)
                            .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const _InfoScreen(),
                          ),
                        );
                      },
                    ),
                    _MoreTile(
                      icon:
                          Icons.privacy_tip_outlined,
                      title: 'Datenschutz',
                      subtitle:
                          'Hinweise zur Datenverarbeitung',
                      onTap: () {
                        Navigator.of(context)
                            .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const LegalScreen(
                              initialSection:
                                  LegalSection
                                      .datenschutz,
                            ),
                          ),
                        );
                      },
                    ),
                    _MoreTile(
                      icon: Icons.gavel_outlined,
                      title:
                          'Kontakt & Verantwortliche Stelle',
                      subtitle:
                          'Interne verantwortliche Stelle',
                      onTap: () {
                        Navigator.of(context)
                            .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const LegalScreen(
                              initialSection:
                                  LegalSection
                                      .kontakt,
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
                      final confirmed =
                          await showDialog<bool>(
                        context: context,
                        builder:
                            (dialogContext) =>
                                AlertDialog(
                          title:
                              const Text('Abmelden?'),
                          content: const Text(
                            'Möchtest du dich wirklich '
                            'aus der App abmelden?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(
                                dialogContext,
                                false,
                              ),
                              child: const Text(
                                'Abbrechen',
                              ),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(
                                dialogContext,
                                true,
                              ),
                              child: const Text(
                                'Abmelden',
                              ),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await PushService
                            .unregisterCurrentDevice();

                        await _supabase.auth
                            .signOut();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      minimumSize:
                          const Size.fromHeight(52),
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
      crossAxisAlignment:
          CrossAxisAlignment.start,
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
            borderRadius:
                BorderRadius.circular(20),
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
      contentPadding:
          const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 5,
      ),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FB),
          borderRadius:
              BorderRadius.circular(13),
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

class _ParentAreaScreen extends StatefulWidget {
  const _ParentAreaScreen();

  @override
  State<_ParentAreaScreen> createState() =>
      _ParentAreaScreenState();
}

class _ParentAreaScreenState
    extends State<_ParentAreaScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _green = Color(0xFF13A05B);
  static const _red = Color(0xFFE30613);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _children = [];
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _attendance = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }

      final links = await _supabase
          .from('parent_child')
          .select('child_id')
          .eq('parent_id', user.id);

      final childIds = links
          .map(
            (row) =>
                row['child_id']?.toString(),
          )
          .whereType<String>()
          .toList();

      List<Map<String, dynamic>> children = [];
      List<Map<String, dynamic>> attendance = [];

      if (childIds.isNotEmpty) {
        final childRows = await _supabase
            .from('profiles')
            .select(
              'id,first_name,last_name,phone,role',
            )
            .inFilter('id', childIds)
            .order('last_name')
            .order('first_name');

        children =
            List<Map<String, dynamic>>.from(
          childRows,
        );

        final attendanceRows = await _supabase
            .from('event_attendance')
            .select(
              'event_id,user_id,status',
            )
            .inFilter('user_id', childIds);

        attendance =
            List<Map<String, dynamic>>.from(
          attendanceRows,
        );
      }

      final eventRows = await _supabase
          .from('events')
          .select(
            'id,title,starts_at,location',
          )
          .gte(
            'starts_at',
            DateTime.now()
                .toUtc()
                .toIso8601String(),
          )
          .order('starts_at')
          .limit(5);

      if (!mounted) return;

      setState(() {
        _children = children;
        _attendance = attendance;
        _events =
            List<Map<String, dynamic>>.from(
          eventRows,
        );
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

  String _name(Map<String, dynamic> child) {
    final first =
        child['first_name']?.toString().trim() ?? '';
    final last =
        child['last_name']?.toString().trim() ?? '';

    final value = '$first $last'.trim();

    return value.isEmpty
        ? 'Jugendmitglied'
        : value;
  }

  String _eventDate(dynamic value) {
    final dt =
        DateTime.tryParse(value?.toString() ?? '')
            ?.toLocal();

    if (dt == null) return 'Kein Datum';

    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year} · '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')} Uhr';
  }

  String _attendanceFor(
    String childId,
    String eventId,
  ) {
    for (final row in _attendance) {
      if (row['user_id']?.toString() ==
              childId &&
          row['event_id']?.toString() ==
              eventId) {
        switch (row['status']?.toString()) {
          case 'zugesagt':
            return 'Zugesagt';

          case 'abgesagt':
            return 'Abgesagt';

          case 'entschuldigt':
            return 'Entschuldigt';

          case 'offen':
            return 'Offen';
        }
      }
    }

    return 'Offen';
  }

  Color _attendanceColor(String value) {
    switch (value) {
      case 'Zugesagt':
        return _green;

      case 'Abgesagt':
        return _red;

      case 'Entschuldigt':
        return const Color(0xFFFF7A00);

      default:
        return const Color(0xFF667085);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06111F),
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Zur Startseite',
            onPressed: () =>
                HomeNavigation.goHome(context),
            icon: const Icon(
              Icons.home_outlined,
            ),
          ),
        ],
        title: const Text('Meine Kinder'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 220),
                  Center(
                    child:
                        CircularProgressIndicator(),
                  ),
                ],
              )
            : ListView(
                padding:
                    const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Container(
                      padding:
                          const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFFFFE6E8,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          14,
                        ),
                      ),
                      child: Text(
                        'Elternbereich konnte '
                        'nicht geladen werden.\n'
                        '$_error',
                        style: const TextStyle(
                          color: _red,
                        ),
                      ),
                    ),
                  if (_error == null &&
                      _children.isEmpty)
                    Container(
                      padding:
                          const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(
                          20,
                        ),
                        border: Border.all(
                          color: const Color(
                            0xFFE3E8EE,
                          ),
                        ),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.family_restroom,
                            size: 54,
                            color: _blue,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Noch kein Jugendmitglied verknüpft',
                            textAlign:
                                TextAlign.center,
                            style: TextStyle(
                              color: _navy,
                              fontSize: 18,
                              fontWeight:
                                  FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Die Verknüpfung kann '
                            'durch einen Ausbilder in '
                            'der Mitgliederverwaltung '
                            'vorgenommen werden.',
                            textAlign:
                                TextAlign.center,
                            style: TextStyle(
                              color: Color(
                                0xFF667085,
                              ),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_error == null &&
                      _children.isNotEmpty) ...[
                    const Text(
                      'Verknüpfte Jugendmitglieder',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 18,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._children.map(
                      (child) => Container(
                        margin:
                            const EdgeInsets.only(
                          bottom: 10,
                        ),
                        padding:
                            const EdgeInsets.all(
                          16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(
                            18,
                          ),
                          border: Border.all(
                            color: const Color(
                              0xFFE3E8EE,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor:
                                  Color(
                                0xFFEAF2FB,
                              ),
                              child: Icon(
                                Icons.person,
                                color: _blue,
                              ),
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Text(
                                    _name(child),
                                    style:
                                        const TextStyle(
                                      color: _navy,
                                      fontSize: 17,
                                      fontWeight:
                                          FontWeight
                                              .w800,
                                    ),
                                  ),
                                  if ((child[
                                                  'phone'] ??
                                              '')
                                          .toString()
                                          .trim()
                                          .isNotEmpty) ...[
                                    const SizedBox(
                                      height: 3,
                                    ),
                                    Text(
                                      child['phone']
                                          .toString(),
                                      style:
                                          const TextStyle(
                                        color: Color(
                                          0xFF667085,
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
                    const SizedBox(height: 12),
                    const Text(
                      'Nächste Termine',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 18,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_events.isEmpty)
                      const Card(
                        child: ListTile(
                          leading: Icon(
                            Icons
                                .event_busy_outlined,
                          ),
                          title: Text(
                            'Keine zukünftigen '
                            'Termine eingetragen.',
                          ),
                        ),
                      )
                    else
                      ..._events.map(
                        (event) {
                          final eventId =
                              event['id']
                                      ?.toString() ??
                                  '';

                          return Container(
                            margin:
                                const EdgeInsets.only(
                              bottom: 12,
                            ),
                            padding:
                                const EdgeInsets.all(
                              16,
                            ),
                            decoration:
                                BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                18,
                              ),
                              border: Border.all(
                                color: const Color(
                                  0xFFE3E8EE,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(
                                  event['title']
                                          ?.toString() ??
                                      'Termin',
                                  style:
                                      const TextStyle(
                                    color: _navy,
                                    fontSize: 17,
                                    fontWeight:
                                        FontWeight
                                            .w800,
                                  ),
                                ),
                                const SizedBox(
                                  height: 4,
                                ),
                                Text(
                                  _eventDate(
                                    event[
                                        'starts_at'],
                                  ),
                                  style:
                                      const TextStyle(
                                    color: Color(
                                      0xFF667085,
                                    ),
                                  ),
                                ),
                                if ((event[
                                                'location'] ??
                                            '')
                                        .toString()
                                        .trim()
                                        .isNotEmpty) ...[
                                  const SizedBox(
                                    height: 2,
                                  ),
                                  Text(
                                    event[
                                            'location']
                                        .toString(),
                                    style:
                                        const TextStyle(
                                      color: Color(
                                        0xFF667085,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(
                                  height: 12,
                                ),
                                ..._children.map(
                                  (child) {
                                    final childId =
                                        child['id']
                                                ?.toString() ??
                                            '';

                                    final status =
                                        _attendanceFor(
                                      childId,
                                      eventId,
                                    );

                                    return Padding(
                                      padding:
                                          const EdgeInsets
                                              .only(
                                        bottom: 6,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child:
                                                Text(
                                              _name(
                                                child,
                                              ),
                                              style:
                                                  const TextStyle(
                                                fontWeight:
                                                    FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal:
                                                  10,
                                              vertical:
                                                  5,
                                            ),
                                            decoration:
                                                BoxDecoration(
                                              color: _attendanceColor(
                                                status,
                                              ).withValues(
                                                alpha:
                                                    0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                999,
                                              ),
                                            ),
                                            child:
                                                Text(
                                              status,
                                              style:
                                                  TextStyle(
                                                color:
                                                    _attendanceColor(
                                                  status,
                                                ),
                                                fontWeight:
                                                    FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 4),
                    const Text(
                      'Teilnahme kann hier nur '
                      'eingesehen werden. '
                      'Rückmeldungen werden weiterhin '
                      'durch das Jugendmitglied selbst '
                      'bzw. durch Ausbilder verwaltet.',
                      style: TextStyle(
                        color: Color(
                          0xFF667085,
                        ),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _MyProfileScreen extends StatefulWidget {
  const _MyProfileScreen();

  @override
  State<_MyProfileScreen> createState() =>
      _MyProfileScreenState();
}

class _MyProfileScreenState
    extends State<_MyProfileScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _red = Color(0xFFE30613);

  final _supabase = Supabase.instance.client;

  final _firstName =
      TextEditingController();
  final _lastName =
      TextEditingController();
  final _phone =
      TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _notificationsEnabled = true;
  bool _eventRemindersEnabled = true;

  int _reminderMinutes = 30;
  String _role = '';
  String? _email;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await _supabase
          .from('profiles')
          .select(
            'first_name,last_name,phone,role,'
            'notifications_enabled,event_reminders_enabled,'
            'reminder_minutes',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      _firstName.text =
          profile?['first_name']?.toString() ?? '';

      _lastName.text =
          profile?['last_name']?.toString() ?? '';

      _phone.text =
          profile?['phone']?.toString() ?? '';

      setState(() {
        _role =
            profile?['role']?.toString() ?? '';
        _email = user.email;

        _notificationsEnabled =
            profile?['notifications_enabled'] !=
                false;

        _eventRemindersEnabled =
            profile?['event_reminders_enabled'] !=
                false;

        _reminderMinutes =
            (profile?['reminder_minutes']
                        as num?)
                    ?.toInt() ??
                30;

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Profil konnte nicht geladen werden: $e',
          ),
        ),
      );
    }
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

  Color _roleColor() {
    switch (_role) {
      case 'ausbilder':
        return const Color(0xFFE30613);

      case 'eltern':
        return const Color(0xFF0B4EA2);

      case 'jugendmitglied':
        return const Color(0xFF13A05B);

      default:
        return const Color(0xFF667085);
    }
  }

  String _displayName() {
    final value =
        '${_firstName.text.trim()} '
        '${_lastName.text.trim()}'
            .trim();

    return value.isEmpty
        ? 'Mein Profil'
        : value;
  }

  Future<void> _save() async {
    final user = _supabase.auth.currentUser;

    if (user == null || _saving) return;

    if (_firstName.text.trim().isEmpty ||
        _lastName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
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
        'first_name':
            _firstName.text.trim(),
        'last_name':
            _lastName.text.trim(),
        'phone': _phone.text.trim().isEmpty
            ? null
            : _phone.text.trim(),
        'notifications_enabled':
            _notificationsEnabled,
        'event_reminders_enabled':
            _eventRemindersEnabled,
        'reminder_minutes':
            _reminderMinutes,
      }).eq('id', user.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content:
              Text('Profil gespeichert.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Speichern fehlgeschlagen: $e',
          ),
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
      backgroundColor: const Color(
        0xFFF3F5F7,
      ),
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Zur Startseite',
            onPressed: () =>
                HomeNavigation.goHome(context),
            icon: const Icon(
              Icons.home_outlined,
            ),
          ),
        ],
        title: const Text('Mein Profil'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : ListView(
              padding:
                  const EdgeInsets.all(18),
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(
                      22,
                    ),
                    border: Border.all(
                      color: const Color(
                        0xFFE3E8EE,
                      ),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 12,
                        offset: Offset(0, 4),
                        color:
                            Color(0x0D000000),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor:
                            _roleColor()
                                .withValues(
                          alpha: 0.12,
                        ),
                        child: Icon(
                          Icons.person,
                          size: 36,
                          color: _roleColor(),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              _displayName(),
                              style:
                                  const TextStyle(
                                color: _navy,
                                fontSize: 20,
                                fontWeight:
                                    FontWeight
                                        .w800,
                              ),
                            ),
                            const SizedBox(
                              height: 5,
                            ),
                            Container(
                              padding:
                                  const EdgeInsets
                                      .symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration:
                                  BoxDecoration(
                                color: _roleColor()
                                    .withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  999,
                                ),
                              ),
                              child: Text(
                                _roleLabel(),
                                style:
                                    TextStyle(
                                  color:
                                      _roleColor(),
                                  fontSize: 12,
                                  fontWeight:
                                      FontWeight
                                          .w800,
                                ),
                              ),
                            ),
                            if ((_email ?? '')
                                .isNotEmpty) ...[
                              const SizedBox(
                                height: 7,
                              ),
                              Text(
                                _email!,
                                overflow:
                                    TextOverflow
                                        .ellipsis,
                                style:
                                    const TextStyle(
                                  color: Color(
                                    0xFF667085,
                                  ),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_role == 'eltern') ...[
                  SizedBox(
                    width: double.infinity,
                    child:
                        OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context)
                            .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const _ParentAreaScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.family_restroom,
                      ),
                      label: const Text(
                        'Meine Kinder öffnen',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                const Align(
                  alignment:
                      Alignment.centerLeft,
                  child: Text(
                    'Persönliche Daten',
                    style: TextStyle(
                      color: _navy,
                      fontSize: 18,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _firstName,
                  textCapitalization:
                      TextCapitalization.words,
                  decoration:
                      const InputDecoration(
                    labelText: 'Vorname',
                    prefixIcon: Icon(
                      Icons.person_outline,
                    ),
                    border:
                        OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lastName,
                  textCapitalization:
                      TextCapitalization.words,
                  decoration:
                      const InputDecoration(
                    labelText: 'Nachname',
                    prefixIcon: Icon(
                      Icons.person_outline,
                    ),
                    border:
                        OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType:
                      TextInputType.phone,
                  decoration:
                      const InputDecoration(
                    labelText: 'Telefon',
                    hintText:
                        'z. B. 0170 1234567',
                    prefixIcon: Icon(
                      Icons.phone_outlined,
                    ),
                    border:
                        OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                    border: Border.all(
                      color: const Color(
                        0xFFE3E8EE,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            _notificationsEnabled
                                ? Icons
                                    .notifications_active_outlined
                                : Icons
                                    .notifications_off_outlined,
                            color:
                                _notificationsEnabled
                                    ? const Color(
                                        0xFF13A05B,
                                      )
                                    : const Color(
                                        0xFF98A2B3,
                                      ),
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          const Expanded(
                            child: Text(
                              'Benachrichtigungen',
                              style:
                                  TextStyle(
                                color: _navy,
                                fontSize: 17,
                                fontWeight:
                                    FontWeight
                                        .w800,
                              ),
                            ),
                          ),
                          Switch(
                            value:
                                _notificationsEnabled,
                            onChanged: (value) {
                              setState(() {
                                _notificationsEnabled =
                                    value;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Align(
                        alignment:
                            Alignment.centerLeft,
                        child: Text(
                          'Termine, Nachrichten, Dokumente und Ausbildung',
                          style: TextStyle(
                            color: Color(
                              0xFF667085,
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 28),
                      SwitchListTile(
                        contentPadding:
                            EdgeInsets.zero,
                        title: const Text(
                          'Automatische Terminerinnerung',
                          style: TextStyle(
                            color: _navy,
                            fontWeight:
                                FontWeight
                                    .w700,
                          ),
                        ),
                        subtitle: const Text(
                          'Gilt für Termine und '
                          'Ausbildungstermine mit '
                          'Startzeit.',
                        ),
                        value:
                            _eventRemindersEnabled,
                        onChanged:
                            _notificationsEnabled
                                ? (value) {
                                    setState(
                                      () {
                                        _eventRemindersEnabled =
                                            value;
                                      },
                                    );
                                  }
                                : null,
                      ),
                      if (_eventRemindersEnabled) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<
                            int>(
                          initialValue:
                              _reminderMinutes,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Erinnerung vor dem Termin',
                            prefixIcon: Icon(
                              Icons
                                  .schedule_outlined,
                            ),
                            border:
                                OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 15,
                              child: Text(
                                '15 Minuten vorher',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 30,
                              child: Text(
                                '30 Minuten vorher',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 60,
                              child: Text(
                                '1 Stunde vorher',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 120,
                              child: Text(
                                '2 Stunden vorher',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 180,
                              child: Text(
                                '3 Stunden vorher',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 1440,
                              child: Text(
                                '1 Tag vorher',
                              ),
                            ),
                          ],
                          onChanged:
                              _notificationsEnabled
                                  ? (value) {
                                      if (value !=
                                          null) {
                                        setState(
                                          () {
                                            _reminderMinutes =
                                                value;
                                          },
                                        );
                                      }
                                    }
                                  : null,
                        ),
                      ],
                    ],
                  ),
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child:
                        OutlinedButton.icon(
                      onPressed: () async {
                        final enabled =
                            await PushService
                                .requestPermissionAndSync();

                        if (!context.mounted) {
                          return;
                        }

                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
                          SnackBar(
                            content: Text(
                              enabled
                                  ? 'Benachrichtigungen auf diesem Gerät sind aktiviert.'
                                  : 'Benachrichtigungen konnten nicht aktiviert werden. '
                                      'Auf dem iPhone die Web-App zuerst zum '
                                      'Home-Bildschirm hinzufügen und '
                                      'Benachrichtigungen erlauben.',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons
                            .notifications_active_outlined,
                      ),
                      label: const Text(
                        'Auf diesem Gerät aktivieren',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child:
                      OutlinedButton.icon(
                    onPressed: () async {
                      final sent =
                          await PushService
                              .sendTestNotification();

                      if (!context.mounted) {
                        return;
                      }

                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        SnackBar(
                          content: Text(
                            sent
                                ? 'Test-Benachrichtigung wurde gesendet.'
                                : 'Test-Benachrichtigung konnte nicht gesendet werden. '
                                    'Bitte Benachrichtigungen auf diesem Gerät '
                                    'zuerst aktivieren.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.send_outlined,
                    ),
                    label: const Text(
                      'Test-Benachrichtigung senden',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed:
                      _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor:
                        Colors.white,
                    minimumSize:
                        const Size.fromHeight(
                      52,
                    ),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.save,
                        ),
                  label: const Text(
                    'Profil speichern',
                  ),
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
      backgroundColor: const Color(
        0xFFF3F5F7,
      ),
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Zur Startseite',
            onPressed: () =>
                HomeNavigation.goHome(context),
            icon: const Icon(
              Icons.home_outlined,
            ),
          ),
        ],
        title: const Text('Über die App'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Center(
            child: Container(
              width: 120,
              height: 120,
              padding:
                  const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(28),
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
                'Die App unterstützt Termine, Ausbildung, '
                'Kommunikation, Dokumente, Projekte und die '
                'Organisation der Jugendfeuerwehr.',
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
        crossAxisAlignment:
            CrossAxisAlignment.start,
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
