import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/home_navigation.dart';
import 'training_attendance_screen.dart';

class TrainingPlansScreen extends StatefulWidget {
  const TrainingPlansScreen({super.key});

  @override
  State<TrainingPlansScreen> createState() => _TrainingPlansScreenState();
}

class _TrainingPlansScreenState extends State<TrainingPlansScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _orange = Color(0xFFFF7A00);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  bool _eventRemindersEnabled = true;
  int _reminderMinutes = 30;
  String? _error;

  List<Map<String, dynamic>> _plans = [];
  String _searchQuery = '';
  String _statusFilter = 'alle';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadProfile(),
      _loadPlans(),
    ]);
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await _supabase
          .from('profiles')
          .select(
            'role,event_reminders_enabled,reminder_minutes',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _isTrainer =
            profile?['role']?.toString().trim().toLowerCase() == 'ausbilder';
        _eventRemindersEnabled =
            profile?['event_reminders_enabled'] != false;
        _reminderMinutes =
            (profile?['reminder_minutes'] as num?)?.toInt() ?? 30;
      });
    } catch (_) {
      // Die Ausbildungsliste soll auch dann öffnen, wenn die
      // Profileinstellungen vorübergehend nicht geladen werden können.
    }
  }

  Future<void> _loadPlans() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final rows = await _supabase
          .from('training_plans')
          .select()
          .order('training_date', ascending: false)
          .order('start_time', ascending: false);

      if (!mounted) return;

      setState(() {
        _plans = List<Map<String, dynamic>>.from(rows);
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

  DateTime? _parseDate(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    return DateTime.tryParse(value.toString());
  }

  String _date(dynamic value) {
    final dt = _parseDate(value);
    if (dt == null) return 'Kein Datum';

    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year}';
  }

  String _time(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '–';

    final parts = raw.split(':');
    if (parts.length < 2) return raw;

    return '${parts[0].padLeft(2, '0')}:'
        '${parts[1].padLeft(2, '0')}';
  }

  String _timeRange(Map<String, dynamic> plan) {
    final start = _time(plan['start_time']);
    final end = _time(plan['end_time']);

    if (start == '–') return 'Keine Uhrzeit';
    if (end == '–') return '$start Uhr';

    return '$start – $end Uhr';
  }

  String _reminderLabel() {
    if (!_eventRemindersEnabled) return 'Ausgeschaltet';

    switch (_reminderMinutes) {
      case 15:
        return '15 Min. vorher';
      case 30:
        return '30 Min. vorher';
      case 60:
        return '1 Std. vorher';
      case 120:
        return '2 Std. vorher';
      case 180:
        return '3 Std. vorher';
      case 1440:
        return '1 Tag vorher';
      default:
        if (_reminderMinutes % 60 == 0) {
          return '${_reminderMinutes ~/ 60} Std. vorher';
        }
        return '$_reminderMinutes Min. vorher';
    }
  }

  String _planStatus(Map<String, dynamic> plan) {
    final date = _parseDate(plan['training_date']);
    if (date == null) return 'geplant';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final planDay = DateTime(date.year, date.month, date.day);

    if (planDay.isBefore(today)) return 'vergangen';
    if (planDay == today) return 'heute';

    return 'geplant';
  }

  String _planStatusLabel(Map<String, dynamic> plan) {
    switch (_planStatus(plan)) {
      case 'heute':
        return 'Heute';
      case 'vergangen':
        return 'Vergangen';
      default:
        return 'Geplant';
    }
  }

  Color _planStatusColor(Map<String, dynamic> plan) {
    switch (_planStatus(plan)) {
      case 'heute':
        return const Color(0xFF13A05B);
      case 'vergangen':
        return const Color(0xFF667085);
      default:
        return _blue;
    }
  }

  List<Map<String, dynamic>> get _filteredPlans {
    final query = _searchQuery.trim().toLowerCase();

    return _plans.where((plan) {
      final title =
          plan['title']?.toString().toLowerCase() ?? '';
      final topic =
          plan['topic']?.toString().toLowerCase() ?? '';
      final location =
          plan['location']?.toString().toLowerCase() ?? '';
      final description =
          plan['description']?.toString().toLowerCase() ?? '';
      final status = _planStatus(plan);

      final matchesQuery =
          query.isEmpty ||
          title.contains(query) ||
          topic.contains(query) ||
          location.contains(query) ||
          description.contains(query);

      final matchesStatus =
          _statusFilter == 'alle' || status == _statusFilter;

      return matchesQuery && matchesStatus;
    }).toList();
  }

  int _statusCount(String status) {
    if (status == 'alle') return _plans.length;

    return _plans
        .where((plan) => _planStatus(plan) == status)
        .length;
  }

  Future<void> _openPlanEditor({
    Map<String, dynamic>? plan,
  }) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TrainingPlanEditor(
        plan: plan,
      ),
    );

    if (changed == true) {
      await _loadPlans();
    }
  }

  Future<void> _openAttendance(
    Map<String, dynamic> plan,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrainingAttendanceScreen(
          plan: plan,
        ),
      ),
    );
  }

  Future<void> _openTrainingRecords() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TrainingRecordsScreen(),
      ),
    );
  }

  Future<void> _deletePlan(
    Map<String, dynamic> plan,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Ausbildungsplan löschen?',
        ),
        content: Text(
          '„${plan['title'] ?? 'Ausbildungsplan'}“ wird gelöscht. '
          'Vorhandene Anwesenheitseinträge zu dieser Ausbildung '
          'werden ebenfalls entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              false,
            ),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              true,
            ),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _supabase
          .from('training_plans')
          .delete()
          .eq('id', plan['id']);

      try {
        await _supabase.functions.invoke(
          'send-push',
          body: {
            'title': 'Ausbildungsplan gelöscht',
            'body':
                '${plan['title'] ?? 'Ausbildungsplan'} wurde entfernt.',
          },
        );
      } catch (pushError) {
        debugPrint(
          'Ausbildungsplan gelöscht, Push fehlgeschlagen: '
          '$pushError',
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ausbildungsplan gelöscht',
          ),
        ),
      );

      await _loadPlans();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Löschen fehlgeschlagen: $e',
          ),
        ),
      );
    }
  }

  void _showDetails(
    Map<String, dynamic> plan,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                plan['title']?.toString() ??
                    'Ausbildungsplan',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 18),
              _TrainingDetailRow(
                icon:
                    Icons.calendar_today_outlined,
                title: 'Datum',
                value:
                    _date(plan['training_date']),
              ),
              _TrainingDetailRow(
                icon: Icons.schedule_outlined,
                title: 'Uhrzeit',
                value: _timeRange(plan),
              ),
              if ((plan['topic'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty)
                _TrainingDetailRow(
                  icon:
                      Icons.menu_book_outlined,
                  title: 'Thema',
                  value:
                      plan['topic'].toString(),
                ),
              if ((plan['location'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty)
                _TrainingDetailRow(
                  icon:
                      Icons.location_on_outlined,
                  title: 'Ort',
                  value:
                      plan['location'].toString(),
                ),
              _TrainingDetailRow(
                icon: _eventRemindersEnabled
                    ? Icons
                        .notifications_active_outlined
                    : Icons
                        .notifications_off_outlined,
                title: 'Erinnerung',
                value: _reminderLabel(),
              ),
              if ((plan['description'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  'Beschreibung',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  plan['description']
                      .toString(),
                ),
              ],
              if (_isTrainer) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(
                        sheetContext,
                      );
                      _openAttendance(plan);
                    },
                    icon: const Icon(
                      Icons.fact_check_outlined,
                    ),
                    label: const Text(
                      'Anwesenheit erfassen',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(
                        sheetContext,
                      );
                      _openPlanEditor(
                        plan: plan,
                      );
                    },
                    icon: const Icon(
                      Icons.edit_outlined,
                    ),
                    label: const Text(
                      'Ausbildungsplan bearbeiten',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor:
            Color(0xFFF3F5F7),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor:
            const Color(0xFFF3F5F7),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding:
                  const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 70,
                    color: _red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ausbildungspläne konnten '
                    'nicht geladen werden.',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight:
                          FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign:
                        TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _loadPlans,
                    icon: const Icon(
                      Icons.refresh,
                    ),
                    label: const Text(
                      'Erneut versuchen',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor:
          const Color(0xFFF3F5F7),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration:
                  const BoxDecoration(
                gradient: LinearGradient(
                  begin:
                      Alignment.topLeft,
                  end:
                      Alignment.bottomRight,
                  colors: [
                    _navy,
                    _blue,
                  ],
                ),
                borderRadius:
                    BorderRadius.only(
                  bottomLeft:
                      Radius.circular(28),
                  bottomRight:
                      Radius.circular(28),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    20,
                    18,
                    20,
                    24,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip:
                            'Zur Startseite',
                        onPressed: () =>
                            HomeNavigation
                                .goHome(
                          context,
                        ),
                        style:
                            IconButton.styleFrom(
                          backgroundColor:
                              Colors.white,
                          foregroundColor:
                              _navy,
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
                            const EdgeInsets
                                .all(5),
                        decoration:
                            BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius
                                  .circular(
                            14,
                          ),
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
                              'Ausbildung',
                              style:
                                  TextStyle(
                                color:
                                    Colors.white,
                                fontSize: 26,
                                fontWeight:
                                    FontWeight
                                        .w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Datum, Uhrzeit, Ort und Thema',
                              style:
                                  TextStyle(
                                color: Colors
                                    .white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isTrainer) ...[
                        IconButton(
                          tooltip:
                              'Ausbildungsnachweise',
                          onPressed:
                              _openTrainingRecords,
                          style:
                              IconButton.styleFrom(
                            backgroundColor:
                                Colors.white,
                            foregroundColor:
                                _navy,
                          ),
                          icon: const Icon(
                            Icons
                                .fact_check_outlined,
                          ),
                        ),
                        const SizedBox(
                          width: 6,
                        ),
                        IconButton(
                          tooltip:
                              'Ausbildungsplan erstellen',
                          onPressed: () =>
                              _openPlanEditor(),
                          style:
                              IconButton.styleFrom(
                            backgroundColor:
                                Colors.white,
                            foregroundColor:
                                _red,
                          ),
                          icon: const Icon(
                            Icons.add,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                16,
                18,
                16,
                8,
              ),
              child: Column(
                children: [
                  TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration:
                        InputDecoration(
                      hintText:
                          'Ausbildungsplan suchen',
                      prefixIcon:
                          const Icon(
                        Icons.search,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius
                                .circular(
                          16,
                        ),
                        borderSide:
                            BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection:
                          Axis.horizontal,
                      children: [
                        ChoiceChip(
                          label: Text(
                            'Alle '
                            '(${_statusCount('alle')})',
                          ),
                          selected:
                              _statusFilter ==
                                  'alle',
                          onSelected: (_) {
                            setState(() {
                              _statusFilter =
                                  'alle';
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(
                            'Geplant '
                            '(${_statusCount('geplant')})',
                          ),
                          selected:
                              _statusFilter ==
                                  'geplant',
                          onSelected: (_) {
                            setState(() {
                              _statusFilter =
                                  'geplant';
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(
                            'Heute '
                            '(${_statusCount('heute')})',
                          ),
                          selected:
                              _statusFilter ==
                                  'heute',
                          onSelected: (_) {
                            setState(() {
                              _statusFilter =
                                  'heute';
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(
                            'Vergangen '
                            '(${_statusCount('vergangen')})',
                          ),
                          selected:
                              _statusFilter ==
                                  'vergangen',
                          onSelected: (_) {
                            setState(() {
                              _statusFilter =
                                  'vergangen';
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                16,
                6,
                16,
                100,
              ),
              child: _buildPlanList(),
            ),
          ],
        ),
      ),
      floatingActionButton: _isTrainer
          ? FloatingActionButton(
              onPressed: () =>
                  _openPlanEditor(),
              backgroundColor: _red,
              foregroundColor:
                  Colors.white,
              child: const Icon(
                Icons.add,
              ),
            )
          : null,
    );
  }

  Widget _buildPlanList() {
    if (_plans.isEmpty) {
      return Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 54,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(22),
          border: Border.all(
            color:
                const Color(0xFFE3E8EE),
          ),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.school_outlined,
              size: 72,
              color: _orange,
            ),
            SizedBox(height: 16),
            Text(
              'Noch keine Ausbildungspläne '
              'vorhanden.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.w700,
                color: _navy,
              ),
            ),
          ],
        ),
      );
    }

    if (_filteredPlans.isEmpty) {
      return Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 40,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(22),
          border: Border.all(
            color:
                const Color(0xFFE3E8EE),
          ),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.search_off,
              size: 60,
              color: _blue,
            ),
            SizedBox(height: 12),
            Text(
              'Keine passenden '
              'Ausbildungspläne gefunden.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _navy,
                fontSize: 16,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _filteredPlans.map(
        (plan) {
          final statusColor =
              _planStatusColor(plan);
          final topic =
              plan['topic']
                      ?.toString()
                      .trim() ??
                  '';
          final location =
              plan['location']
                      ?.toString()
                      .trim() ??
                  '';

          return Container(
            margin:
                const EdgeInsets.only(
              bottom: 12,
            ),
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
              boxShadow: const [
                BoxShadow(
                  blurRadius: 12,
                  offset: Offset(0, 4),
                  color:
                      Color(0x0D000000),
                ),
              ],
            ),
            child: InkWell(
              onTap: () =>
                  _showDetails(plan),
              borderRadius:
                  BorderRadius.circular(
                20,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration:
                          BoxDecoration(
                        color: const Color(
                          0xFFFFF0E0,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          16,
                        ),
                      ),
                      child: const Icon(
                        Icons.school_outlined,
                        color: _orange,
                        size: 30,
                      ),
                    ),
                    const SizedBox(
                      width: 13,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  plan['title']
                                          ?.toString() ??
                                      'Ausbildungsplan',
                                  style:
                                      const TextStyle(
                                    color: _navy,
                                    fontSize:
                                        18,
                                    fontWeight:
                                        FontWeight
                                            .w800,
                                  ),
                                ),
                              ),
                              Container(
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  horizontal:
                                      8,
                                  vertical:
                                      4,
                                ),
                                decoration:
                                    BoxDecoration(
                                  color:
                                      statusColor
                                          .withValues(
                                    alpha:
                                        0.12,
                                  ),
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    999,
                                  ),
                                ),
                                child: Text(
                                  _planStatusLabel(
                                    plan,
                                  ),
                                  style:
                                      TextStyle(
                                    color:
                                        statusColor,
                                    fontSize:
                                        11,
                                    fontWeight:
                                        FontWeight
                                            .w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (topic
                              .isNotEmpty) ...[
                            const SizedBox(
                              height: 5,
                            ),
                            Text(
                              topic,
                              style:
                                  const TextStyle(
                                color: _blue,
                                fontWeight:
                                    FontWeight
                                        .w700,
                              ),
                            ),
                          ],
                          const SizedBox(
                            height: 10,
                          ),
                          _CompactInfo(
                            icon: Icons
                                .calendar_today_outlined,
                            text: _date(
                              plan[
                                  'training_date'],
                            ),
                          ),
                          const SizedBox(
                            height: 6,
                          ),
                          _CompactInfo(
                            icon: Icons
                                .schedule_outlined,
                            text:
                                _timeRange(
                              plan,
                            ),
                          ),
                          if (location
                              .isNotEmpty) ...[
                            const SizedBox(
                              height: 6,
                            ),
                            _CompactInfo(
                              icon: Icons
                                  .location_on_outlined,
                              text: location,
                            ),
                          ],
                          const SizedBox(
                            height: 6,
                          ),
                          _CompactInfo(
                            icon:
                                _eventRemindersEnabled
                                    ? Icons
                                        .notifications_active_outlined
                                    : Icons
                                        .notifications_off_outlined,
                            text:
                                'Erinnerung: '
                                '${_reminderLabel()}',
                          ),
                          if (_isTrainer) ...[
                            const SizedBox(
                              height: 10,
                            ),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment
                                      .end,
                              children: [
                                IconButton(
                                  tooltip:
                                      'Anwesenheit',
                                  onPressed: () =>
                                      _openAttendance(
                                    plan,
                                  ),
                                  icon:
                                      const Icon(
                                    Icons
                                        .fact_check_outlined,
                                    color:
                                        _blue,
                                  ),
                                ),
                                IconButton(
                                  tooltip:
                                      'Bearbeiten',
                                  onPressed: () =>
                                      _openPlanEditor(
                                    plan: plan,
                                  ),
                                  icon:
                                      const Icon(
                                    Icons
                                        .edit_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip:
                                      'Löschen',
                                  onPressed: () =>
                                      _deletePlan(
                                    plan,
                                  ),
                                  icon:
                                      const Icon(
                                    Icons
                                        .delete_outline,
                                    color:
                                        _red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ).toList(),
    );
  }
}

class _TrainingPlanEditor extends StatefulWidget {
  final Map<String, dynamic>? plan;

  const _TrainingPlanEditor({
    this.plan,
  });

  @override
  State<_TrainingPlanEditor> createState() =>
      _TrainingPlanEditorState();
}

class _TrainingPlanEditorState
    extends State<_TrainingPlanEditor> {
  final _formKey = GlobalKey<FormState>();
  final _supabase =
      Supabase.instance.client;

  late final TextEditingController _title;
  late final TextEditingController _topic;
  late final TextEditingController
      _location;
  late final TextEditingController
      _description;

  DateTime? _trainingDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _title = TextEditingController(
      text: widget.plan?['title']
              ?.toString() ??
          '',
    );

    _topic = TextEditingController(
      text: widget.plan?['topic']
              ?.toString() ??
          '',
    );

    _location = TextEditingController(
      text: widget.plan?['location']
              ?.toString() ??
          '',
    );

    _description =
        TextEditingController(
      text: widget.plan?['description']
              ?.toString() ??
          '',
    );

    _trainingDate =
        DateTime.tryParse(
      widget.plan?['training_date']
              ?.toString() ??
          '',
    );

    _startTime = _parseTime(
      widget.plan?['start_time'],
    );

    _endTime = _parseTime(
      widget.plan?['end_time'],
    );
  }

  TimeOfDay? _parseTime(
    dynamic value,
  ) {
    final raw =
        value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;

    final parts = raw.split(':');
    if (parts.length < 2) return null;

    final hour =
        int.tryParse(parts[0]);
    final minute =
        int.tryParse(parts[1]);

    if (hour == null ||
        minute == null) {
      return null;
    }

    return TimeOfDay(
      hour: hour,
      minute: minute,
    );
  }

  String _isoDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _dbTime(TimeOfDay? value) {
    if (value == null) return '';

    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}:00';
  }

  String _displayDate(
    DateTime? date,
  ) {
    if (date == null) {
      return 'Datum auswählen';
    }

    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  String _displayTime(
    TimeOfDay? time,
  ) {
    if (time == null) {
      return 'Uhrzeit auswählen';
    }

    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')} Uhr';
  }

  Future<void> _pickDate() async {
    final picked =
        await showDatePicker(
      context: context,
      initialDate:
          _trainingDate ??
              DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      _trainingDate = picked;
    });
  }

  Future<void> _pickTime(
    bool start,
  ) async {
    final current =
        start ? _startTime : _endTime;

    final picked =
        await showTimePicker(
      context: context,
      initialTime:
          current ?? TimeOfDay.now(),
    );

    if (picked == null) return;

    setState(() {
      if (start) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  int _minutesOfDay(
    TimeOfDay time,
  ) {
    return time.hour * 60 +
        time.minute;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!
        .validate()) {
      return;
    }

    if (_trainingDate == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte ein Datum auswählen.',
          ),
        ),
      );
      return;
    }

    if (_startTime == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte eine Startzeit auswählen.',
          ),
        ),
      );
      return;
    }

    if (_endTime != null &&
        _minutesOfDay(_endTime!) <=
            _minutesOfDay(
              _startTime!,
            )) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Die Endzeit muss nach '
            'der Startzeit liegen.',
          ),
        ),
      );
      return;
    }

    final user =
        _supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      _saving = true;
    });

    final data =
        <String, dynamic>{
      'title': _title.text.trim(),
      'topic':
          _topic.text.trim().isEmpty
              ? null
              : _topic.text.trim(),
      'location':
          _location.text.trim().isEmpty
              ? null
              : _location.text.trim(),
      'description':
          _description.text
                  .trim()
                  .isEmpty
              ? null
              : _description.text.trim(),
      'training_date':
          _isoDate(_trainingDate!),
      'start_time':
          _dbTime(_startTime),
      'end_time': _endTime == null
          ? null
          : _dbTime(_endTime),
      'valid_from':
          _isoDate(_trainingDate!),
      'valid_until':
          _isoDate(_trainingDate!),
    };

    try {
      if (widget.plan == null) {
        await _supabase
            .from('training_plans')
            .insert({
          ...data,
          'created_by': user.id,
        });

        try {
          await _supabase.functions
              .invoke(
            'send-push',
            body: {
              'title':
                  'Neuer Ausbildungsplan',
              'body': _topic.text
                      .trim()
                      .isEmpty
                  ? _title.text.trim()
                  : _topic.text.trim(),
            },
          );
        } catch (pushError) {
          debugPrint(
            'Ausbildungsplan gespeichert, '
            'Push fehlgeschlagen: '
            '$pushError',
          );
        }
      } else {
        await _supabase
            .from('training_plans')
            .update(data)
            .eq(
              'id',
              widget.plan!['id'],
            );

        try {
          await _supabase.functions
              .invoke(
            'send-push',
            body: {
              'title':
                  'Ausbildungsplan geändert',
              'body': _topic.text
                      .trim()
                      .isEmpty
                  ? _title.text.trim()
                  : _topic.text.trim(),
            },
          );
        } catch (pushError) {
          debugPrint(
            'Ausbildungsplan geändert, '
            'Push fehlgeschlagen: '
            '$pushError',
          );
        }
      }

      if (!mounted) return;

      Navigator.pop(
        context,
        true,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Speichern fehlgeschlagen: '
            '$e',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _topic.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom:
            MediaQuery.of(context)
                    .viewInsets
                    .bottom +
                20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                widget.plan == null
                    ? 'Ausbildungsplan erstellen'
                    : 'Ausbildungsplan bearbeiten',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _title,
                decoration:
                    const InputDecoration(
                  labelText: 'Titel *',
                  border:
                      OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null ||
                      value
                          .trim()
                          .isEmpty) {
                    return 'Bitte einen Titel eingeben.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _topic,
                decoration:
                    const InputDecoration(
                  labelText: 'Thema *',
                  prefixIcon: Icon(
                    Icons
                        .menu_book_outlined,
                  ),
                  border:
                      OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null ||
                      value
                          .trim()
                          .isEmpty) {
                    return 'Bitte ein Thema eingeben.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding:
                    EdgeInsets.zero,
                leading: const Icon(
                  Icons
                      .calendar_today_outlined,
                ),
                title:
                    const Text('Datum *'),
                subtitle: Text(
                  _displayDate(
                    _trainingDate,
                  ),
                ),
                trailing: const Icon(
                  Icons
                      .edit_calendar_outlined,
                ),
                onTap: _pickDate,
              ),
              ListTile(
                contentPadding:
                    EdgeInsets.zero,
                leading: const Icon(
                  Icons.schedule_outlined,
                ),
                title: const Text(
                  'Startzeit *',
                ),
                subtitle: Text(
                  _displayTime(
                    _startTime,
                  ),
                ),
                trailing: const Icon(
                  Icons.access_time,
                ),
                onTap: () =>
                    _pickTime(true),
              ),
              ListTile(
                contentPadding:
                    EdgeInsets.zero,
                leading: const Icon(
                  Icons.schedule,
                ),
                title:
                    const Text('Endzeit'),
                subtitle: Text(
                  _displayTime(
                    _endTime,
                  ),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    if (_endTime != null)
                      IconButton(
                        tooltip:
                            'Endzeit entfernen',
                        onPressed: () {
                          setState(() {
                            _endTime =
                                null;
                          });
                        },
                        icon:
                            const Icon(
                          Icons.close,
                        ),
                      ),
                    IconButton(
                      tooltip:
                          'Endzeit auswählen',
                      onPressed: () =>
                          _pickTime(
                        false,
                      ),
                      icon: const Icon(
                        Icons.access_time,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _location,
                decoration:
                    const InputDecoration(
                  labelText: 'Ort *',
                  prefixIcon: Icon(
                    Icons
                        .location_on_outlined,
                  ),
                  border:
                      OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null ||
                      value
                          .trim()
                          .isEmpty) {
                    return 'Bitte einen Ort eingeben.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 6,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Beschreibung',
                  border:
                      OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child:
                    FilledButton.icon(
                  onPressed:
                      _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.save,
                        ),
                  label: Text(
                    widget.plan == null
                        ? 'Erstellen'
                        : 'Speichern',
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

class _CompactInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CompactInfo({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color:
              const Color(0xFF73808F),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color:
                  Color(0xFF4B5563),
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrainingDetailRow
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _TrainingDetailRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 14,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color:
                const Color(0xFFE30613),
            size: 22,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(
              title,
              style:
                  const TextStyle(
                color:
                    Color(0xFF667085),
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(
                color:
                    Color(0xFF101828),
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
