import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/home_navigation.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);
  static const _orange = Color(0xFFFF7A00);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _allowed = false;
  String? _error;

  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _trainers = [];

  String _statusFilter = 'alle';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
          .select('role,approval_status')
          .eq('id', user.id)
          .maybeSingle();

      final isTrainer =
          profile?['role']?.toString().trim().toLowerCase() == 'ausbilder' &&
              profile?['approval_status']?.toString() == 'approved';

      if (!isTrainer) {
        if (!mounted) return;
        setState(() {
          _allowed = false;
          _loading = false;
        });
        return;
      }

      final results = await Future.wait([
        _supabase
            .from('projects')
            .select()
            .order('updated_at', ascending: false),
        _supabase
            .from('project_tasks')
            .select()
            .order('due_date', ascending: true),
        _supabase
            .from('profiles')
            .select('id,first_name,last_name,role,approval_status')
            .eq('role', 'ausbilder')
            .eq('approval_status', 'approved')
            .order('last_name'),
      ]);

      if (!mounted) return;

      setState(() {
        _allowed = true;
        _projects = List<Map<String, dynamic>>.from(results[0]);
        _tasks = List<Map<String, dynamic>>.from(results[1]);
        _trainers = List<Map<String, dynamic>>.from(results[2]);
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

  List<Map<String, dynamic>> get _visibleProjects {
    if (_statusFilter == 'alle') return _projects;

    return _projects
        .where((project) => project['status']?.toString() == _statusFilter)
        .toList();
  }

  List<Map<String, dynamic>> _tasksFor(String projectId) {
    return _tasks
        .where((task) => task['project_id']?.toString() == projectId)
        .toList();
  }

  int _doneTasks(String projectId) {
    return _tasksFor(projectId)
        .where((task) => task['status']?.toString() == 'erledigt')
        .length;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'aktiv':
        return 'Aktiv';
      case 'pausiert':
        return 'Pausiert';
      case 'abgeschlossen':
        return 'Abgeschlossen';
      case 'planung':
      default:
        return 'Planung';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'aktiv':
        return _green;
      case 'pausiert':
        return _orange;
      case 'abgeschlossen':
        return _blue;
      case 'planung':
      default:
        return _navy;
    }
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '';

    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  String _dateRange(Map<String, dynamic> project) {
    final start = _formatDate(project['start_date']);
    final end = _formatDate(project['end_date']);

    if (start.isEmpty && end.isEmpty) return 'Noch kein Zeitraum festgelegt';
    if (start.isNotEmpty && end.isEmpty) return 'Ab $start';
    if (start.isEmpty && end.isNotEmpty) return 'Bis $end';

    return '$start – $end';
  }

  Future<void> _createProject() async {
    final draft = await showModalBottomSheet<_ProjectDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ProjectEditorSheet(),
    );

    if (draft == null) return;

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('projects').insert({
        'title': draft.title,
        'description': draft.description.isEmpty ? null : draft.description,
        'location': draft.location.isEmpty ? null : draft.location,
        'status': draft.status,
        'start_date': _isoDate(draft.startDate),
        'end_date': _isoDate(draft.endDate),
        'created_by': user.id,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Projekt wurde angelegt.')),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Projekt konnte nicht angelegt werden: $e')),
      );
    }
  }

  Future<void> _openProject(Map<String, dynamic> project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(
          project: Map<String, dynamic>.from(project),
          trainers: _trainers,
        ),
      ),
    );

    await _load();
  }

  String? _isoDate(DateTime? date) {
    if (date == null) return null;

    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_allowed) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F5F7),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 72,
                    color: _navy,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Nur für Ausbilder',
                    style: TextStyle(
                      color: _navy,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Der Projektbereich ist ausschließlich für '
                    'freigegebene Ausbilder verfügbar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF667085),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => HomeNavigation.goHome(context),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Zur Startseite'),
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
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _ProjectsHeader(onHome: () => HomeNavigation.goHome(context)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: _red),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProjectSummary(
                    projects: _projects,
                    tasks: _tasks,
                  ),
                  const SizedBox(height: 18),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _StatusFilterChip(
                          label: 'Alle',
                          value: 'alle',
                          selected: _statusFilter == 'alle',
                          onSelected: (value) {
                            setState(() => _statusFilter = value);
                          },
                        ),
                        const SizedBox(width: 8),
                        _StatusFilterChip(
                          label: 'Planung',
                          value: 'planung',
                          selected: _statusFilter == 'planung',
                          onSelected: (value) {
                            setState(() => _statusFilter = value);
                          },
                        ),
                        const SizedBox(width: 8),
                        _StatusFilterChip(
                          label: 'Aktiv',
                          value: 'aktiv',
                          selected: _statusFilter == 'aktiv',
                          onSelected: (value) {
                            setState(() => _statusFilter = value);
                          },
                        ),
                        const SizedBox(width: 8),
                        _StatusFilterChip(
                          label: 'Pausiert',
                          value: 'pausiert',
                          selected: _statusFilter == 'pausiert',
                          onSelected: (value) {
                            setState(() => _statusFilter = value);
                          },
                        ),
                        const SizedBox(width: 8),
                        _StatusFilterChip(
                          label: 'Abgeschlossen',
                          value: 'abgeschlossen',
                          selected: _statusFilter == 'abgeschlossen',
                          onSelected: (value) {
                            setState(() => _statusFilter = value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_visibleProjects.isEmpty)
                    const _EmptyProjects()
                  else
                    ..._visibleProjects.map((project) {
                      final id = project['id']?.toString() ?? '';
                      final tasks = _tasksFor(id);
                      final done = _doneTasks(id);
                      final total = tasks.length;
                      final progress = total == 0 ? 0.0 : done / total;
                      final status =
                          project['status']?.toString() ?? 'planung';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            onTap: () => _openProject(project),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFE3E8EE),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: _statusColor(status)
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          Icons.account_tree_outlined,
                                          color: _statusColor(status),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              project['title']?.toString() ??
                                                  'Projekt',
                                              style: const TextStyle(
                                                color: _navy,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              children: [
                                                _SmallBadge(
                                                  text: _statusLabel(status),
                                                  color: _statusColor(status),
                                                ),
                                                if ((project['location']
                                                            ?.toString() ??
                                                        '')
                                                    .isNotEmpty)
                                                  _SmallBadge(
                                                    text: project['location']
                                                        .toString(),
                                                    color: _blue,
                                                    icon: Icons.place_outlined,
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right,
                                        color: Color(0xFF98A2B3),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.date_range_outlined,
                                        size: 18,
                                        color: Color(0xFF667085),
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          _dateRange(project),
                                          style: const TextStyle(
                                            color: Color(0xFF667085),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Text(
                                        total == 0
                                            ? 'Noch keine Aufgaben'
                                            : '$done von $total Aufgaben erledigt',
                                        style: const TextStyle(
                                          color: _navy,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (total > 0)
                                        Text(
                                          '${(progress * 100).round()} %',
                                          style: TextStyle(
                                            color: _statusColor(status),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (total > 0) ...[
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 8,
                                        backgroundColor:
                                            const Color(0xFFE9EEF4),
                                        color: _statusColor(status),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        backgroundColor: _red,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Projekt'),
      ),
    );
  }
}

class _ProjectsHeader extends StatelessWidget {
  final VoidCallback onHome;

  const _ProjectsHeader({
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A1F44);
    const blue = Color(0xFF0B4EA2);

    return Container(
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
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Zur Startseite',
                onPressed: onHome,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: navy,
                ),
                icon: const Icon(Icons.home_outlined),
              ),
              const SizedBox(width: 10),
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
                      'Projekte',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Planung nur für Ausbilder',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.admin_panel_settings_outlined,
                color: Colors.white,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectSummary extends StatelessWidget {
  final List<Map<String, dynamic>> projects;
  final List<Map<String, dynamic>> tasks;

  const _ProjectSummary({
    required this.projects,
    required this.tasks,
  });

  @override
  Widget build(BuildContext context) {
    final active =
        projects.where((p) => p['status']?.toString() == 'aktiv').length;
    final planning =
        projects.where((p) => p['status']?.toString() == 'planung').length;
    final openTasks =
        tasks.where((t) => t['status']?.toString() != 'erledigt').length;

    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            value: '$active',
            label: 'aktiv',
            icon: Icons.play_circle_outline,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            value: '$planning',
            label: 'in Planung',
            icon: Icons.edit_calendar_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            value: '$openTasks',
            label: 'Aufgaben offen',
            icon: Icons.task_alt_outlined,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _SummaryTile({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E8EE)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: const Color(0xFF0B4EA2),
            size: 23,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0A1F44),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final ValueChanged<String> onSelected;

  const _StatusFilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const _SmallBadge({
    required this.text,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3E8EE)),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 68,
            color: Color(0xFF0B4EA2),
          ),
          SizedBox(height: 14),
          Text(
            'Noch keine Projekte',
            style: TextStyle(
              color: Color(0xFF0A1F44),
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Lege das erste Projekt an und verteile anschließend Aufgaben.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF667085),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class ProjectDetailScreen extends StatefulWidget {
  final Map<String, dynamic> project;
  final List<Map<String, dynamic>> trainers;

  const ProjectDetailScreen({
    super.key,
    required this.project,
    required this.trainers,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);
  static const _orange = Color(0xFFFF7A00);

  final _supabase = Supabase.instance.client;

  late Map<String, dynamic> _project;

  bool _loading = true;
  List<Map<String, dynamic>> _tasks = [];

  @override
  void initState() {
    super.initState();
    _project = Map<String, dynamic>.from(widget.project);
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      final rows = await _supabase
          .from('project_tasks')
          .select()
          .eq('project_id', _project['id'])
          .order('due_at', ascending: true)
          .order('created_at');

      if (!mounted) return;

      setState(() {
        _tasks = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aufgaben konnten nicht geladen werden: $e')),
      );
    }
  }

  String _trainerName(dynamic id) {
    if (id == null) return 'Nicht zugewiesen';

    final target = id.toString();

    for (final trainer in widget.trainers) {
      if (trainer['id']?.toString() == target) {
        final first = trainer['first_name']?.toString().trim() ?? '';
        final last = trainer['last_name']?.toString().trim() ?? '';
        final name = '$first $last'.trim();
        return name.isEmpty ? 'Ausbilder' : name;
      }
    }

    return 'Ausbilder';
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '';

    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  String _formatTaskDue(Map<String, dynamic> task) {
    final dueAt = DateTime.tryParse(task['due_at']?.toString() ?? '')?.toLocal();

    if (dueAt != null) {
      return '${dueAt.day.toString().padLeft(2, '0')}.'
          '${dueAt.month.toString().padLeft(2, '0')}.'
          '${dueAt.year} · '
          '${dueAt.hour.toString().padLeft(2, '0')}:'
          '${dueAt.minute.toString().padLeft(2, '0')} Uhr';
    }

    final dueDate = _formatDate(task['due_date']);
    return dueDate.isEmpty ? 'Keine Fälligkeit' : dueDate;
  }

  String _reminderLabel(int minutes) {
    if (minutes == 1440) return '1 Tag vorher';
    if (minutes == 2880) return '2 Tage vorher';
    if (minutes == 10080) return '1 Woche vorher';
    if (minutes == 60) return '1 Stunde vorher';
    if (minutes == 120) return '2 Stunden vorher';
    if (minutes == 180) return '3 Stunden vorher';
    return '$minutes Minuten vorher';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'aktiv':
        return 'Aktiv';
      case 'pausiert':
        return 'Pausiert';
      case 'abgeschlossen':
        return 'Abgeschlossen';
      case 'planung':
      default:
        return 'Planung';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'aktiv':
        return _green;
      case 'pausiert':
        return _orange;
      case 'abgeschlossen':
        return _blue;
      case 'planung':
      default:
        return _navy;
    }
  }

  String _taskStatusLabel(String status) {
    switch (status) {
      case 'in_arbeit':
        return 'In Arbeit';
      case 'erledigt':
        return 'Erledigt';
      case 'offen':
      default:
        return 'Offen';
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'hoch':
        return _red;
      case 'niedrig':
        return _blue;
      case 'normal':
      default:
        return _orange;
    }
  }

  Future<void> _addTask() async {
    final draft = await showModalBottomSheet<_TaskDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TaskEditorSheet(
        trainers: widget.trainers,
      ),
    );

    if (draft == null) return;

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('project_tasks').insert({
        'project_id': _project['id'],
        'title': draft.title,
        'description': draft.description.isEmpty ? null : draft.description,
        'assigned_to': draft.assignedTo,
        'due_date': _isoDate(draft.dueDate),
        'due_at': draft.dueAt?.toUtc().toIso8601String(),
        'reminder_enabled': draft.reminderEnabled,
        'reminder_minutes': draft.reminderMinutes,
        'status': draft.status,
        'priority': draft.priority,
        'created_by': user.id,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aufgabe wurde angelegt.')),
      );

      await _loadTasks();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aufgabe konnte nicht angelegt werden: $e')),
      );
    }
  }

  Future<void> _editTask(Map<String, dynamic> task) async {
    final draft = await showModalBottomSheet<_TaskDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TaskEditorSheet(
        trainers: widget.trainers,
        task: task,
      ),
    );

    if (draft == null) return;

    try {
      await _supabase
          .from('project_tasks')
          .update({
            'title': draft.title,
            'description':
                draft.description.isEmpty ? null : draft.description,
            'assigned_to': draft.assignedTo,
            'due_date': _isoDate(draft.dueDate),
            'due_at': draft.dueAt?.toUtc().toIso8601String(),
            'reminder_enabled': draft.reminderEnabled,
            'reminder_minutes': draft.reminderMinutes,
            'status': draft.status,
            'priority': draft.priority,
          })
          .eq('id', task['id']);

      await _loadTasks();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aufgabe konnte nicht geändert werden: $e')),
      );
    }
  }

  Future<void> _toggleTask(Map<String, dynamic> task, bool done) async {
    try {
      await _supabase
          .from('project_tasks')
          .update({'status': done ? 'erledigt' : 'offen'})
          .eq('id', task['id']);

      await _loadTasks();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aufgabe konnte nicht geändert werden: $e')),
      );
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aufgabe löschen?'),
        content: Text(
          '„${task['title'] ?? 'Aufgabe'}“ wird dauerhaft gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _supabase.from('project_tasks').delete().eq('id', task['id']);
    await _loadTasks();
  }

  Future<void> _editProject() async {
    final draft = await showModalBottomSheet<_ProjectDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProjectEditorSheet(project: _project),
    );

    if (draft == null) return;

    try {
      final updated = await _supabase
          .from('projects')
          .update({
            'title': draft.title,
            'description': draft.description.isEmpty ? null : draft.description,
            'location': draft.location.isEmpty ? null : draft.location,
            'status': draft.status,
            'start_date': _isoDate(draft.startDate),
            'end_date': _isoDate(draft.endDate),
          })
          .eq('id', _project['id'])
          .select()
          .single();

      if (!mounted) return;

      setState(() {
        _project = Map<String, dynamic>.from(updated);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Projekt konnte nicht geändert werden: $e')),
      );
    }
  }

  Future<void> _deleteProject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Projekt löschen?'),
        content: Text(
          '„${_project['title'] ?? 'Projekt'}“ und alle zugehörigen '
          'Aufgaben werden dauerhaft gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Projekt löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase.from('projects').delete().eq('id', _project['id']);

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Projekt konnte nicht gelöscht werden: $e')),
      );
    }
  }

  String? _isoDate(DateTime? date) {
    if (date == null) return null;

    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final status = _project['status']?.toString() ?? 'planung';
    final done =
        _tasks.where((task) => task['status']?.toString() == 'erledigt').length;
    final total = _tasks.length;
    final progress = total == 0 ? 0.0 : done / total;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: const Text('Projekt'),
        actions: [
          IconButton(
            tooltip: 'Projekt bearbeiten',
            onPressed: _editProject,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                _deleteProject();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Projekt löschen'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTasks,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _statusColor(status),
                    _statusColor(status).withValues(alpha: 0.78),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SmallBadge(
                    text: _statusLabel(status),
                    color: Colors.white,
                    icon: Icons.flag_outlined,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _project['title']?.toString() ?? 'Projekt',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if ((_project['description']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      _project['description'].toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 15),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if ((_project['start_date']?.toString() ?? '').isNotEmpty)
                        _WhiteMeta(
                          icon: Icons.calendar_today_outlined,
                          text: _formatDate(_project['start_date']),
                        ),
                      if ((_project['end_date']?.toString() ?? '').isNotEmpty)
                        _WhiteMeta(
                          icon: Icons.event_available_outlined,
                          text: 'bis ${_formatDate(_project['end_date'])}',
                        ),
                      if ((_project['location']?.toString() ?? '').isNotEmpty)
                        _WhiteMeta(
                          icon: Icons.place_outlined,
                          text: _project['location'].toString(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE3E8EE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Fortschritt',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$done / $total',
                        style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : progress,
                      minHeight: 10,
                      backgroundColor: const Color(0xFFE9EEF4),
                      color: _statusColor(status),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Projektplanung',
                style: TextStyle(
                  color: _navy,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Column(
              children: [
                _ProjectToolTile(
                  icon: Icons.checklist_outlined,
                  title: 'Checkliste',
                  subtitle: 'Einfache Punkte abhaken und den Überblick behalten',
                  color: _green,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _ProjectChecklistScreen(
                          projectId: _project['id'].toString(),
                          projectTitle:
                              _project['title']?.toString() ?? 'Projekt',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 9),
                _ProjectToolTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Material & Kosten',
                  subtitle: 'Materialbedarf, geplante und tatsächliche Kosten',
                  color: _orange,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _ProjectMaterialsScreen(
                          projectId: _project['id'].toString(),
                          projectTitle:
                              _project['title']?.toString() ?? 'Projekt',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 9),
                _ProjectToolTile(
                  icon: Icons.folder_copy_outlined,
                  title: 'Dokumente',
                  subtitle: 'Projektdateien sicher nur für Ausbilder speichern',
                  color: _blue,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _ProjectDocumentsScreen(
                          projectId: _project['id'].toString(),
                          projectTitle:
                              _project['title']?.toString() ?? 'Projekt',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Aufgaben',
                    style: TextStyle(
                      color: _navy,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _addTask,
                  icon: const Icon(Icons.add_task),
                  label: const Text('Aufgabe'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_tasks.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 34,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE3E8EE)),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.task_alt_outlined,
                      size: 52,
                      color: _blue,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Noch keine Aufgaben',
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._tasks.map((task) {
                final taskStatus = task['status']?.toString() ?? 'offen';
                final priority = task['priority']?.toString() ?? 'normal';
                final isDone = taskStatus == 'erledigt';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDone
                            ? _green.withValues(alpha: 0.28)
                            : const Color(0xFFE3E8EE),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: isDone,
                            onChanged: (value) {
                              _toggleTask(task, value ?? false);
                            },
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task['title']?.toString() ?? 'Aufgabe',
                                    style: TextStyle(
                                      color: _navy,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      decoration: isDone
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 7,
                                    runSpacing: 6,
                                    children: [
                                      _SmallBadge(
                                        text: _taskStatusLabel(taskStatus),
                                        color: isDone ? _green : _navy,
                                      ),
                                      _SmallBadge(
                                        text: priority == 'hoch'
                                            ? 'Hohe Priorität'
                                            : priority == 'niedrig'
                                                ? 'Niedrige Priorität'
                                                : 'Normal',
                                        color: _priorityColor(priority),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.person_outline,
                                        size: 17,
                                        color: Color(0xFF667085),
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          _trainerName(task['assigned_to']),
                                          style: const TextStyle(
                                            color: Color(0xFF667085),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if ((task['due_at']?.toString() ?? '')
                                          .isNotEmpty ||
                                      (task['due_date']?.toString() ?? '')
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.event_outlined,
                                          size: 17,
                                          color: Color(0xFF667085),
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            'Fällig: ${_formatTaskDue(task)}',
                                            style: const TextStyle(
                                              color: Color(0xFF667085),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (task['reminder_enabled'] != false &&
                                        (task['due_at']?.toString() ?? '')
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.notifications_active_outlined,
                                            size: 17,
                                            color: Color(0xFF667085),
                                          ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: Text(
                                              'Erinnerung: ${_reminderLabel(
                                                (task['reminder_minutes']
                                                            as num?)
                                                        ?.toInt() ??
                                                    1440,
                                              )}',
                                              style: const TextStyle(
                                                color: Color(0xFF667085),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                _editTask(task);
                              } else if (value == 'delete') {
                                _deleteTask(task);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('Bearbeiten'),
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
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _WhiteMeta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WhiteMeta({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 17),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ProjectDraft {
  final String title;
  final String description;
  final String location;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;

  const _ProjectDraft({
    required this.title,
    required this.description,
    required this.location,
    required this.status,
    required this.startDate,
    required this.endDate,
  });
}

class _ProjectEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? project;

  const _ProjectEditorSheet({
    this.project,
  });

  @override
  State<_ProjectEditorSheet> createState() => _ProjectEditorSheetState();
}

class _ProjectEditorSheetState extends State<_ProjectEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;

  String _status = 'planung';
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();

    final project = widget.project;

    _title = TextEditingController(
      text: project?['title']?.toString() ?? '',
    );
    _description = TextEditingController(
      text: project?['description']?.toString() ?? '',
    );
    _location = TextEditingController(
      text: project?['location']?.toString() ?? '',
    );

    _status = project?['status']?.toString() ?? 'planung';
    _startDate = DateTime.tryParse(project?['start_date']?.toString() ?? '');
    _endDate = DateTime.tryParse(project?['end_date']?.toString() ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Nicht festgelegt';

    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  Future<void> _pickStart() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );

    if (result != null) {
      setState(() {
        _startDate = result;
        if (_endDate != null && _endDate!.isBefore(result)) {
          _endDate = result;
        }
      });
    }
  }

  Future<void> _pickEnd() async {
    final initial = _endDate ?? _startDate ?? DateTime.now();

    final result = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2040),
    );

    if (result != null) {
      setState(() => _endDate = result);
    }
  }

  void _save() {
    final title = _title.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Projektnamen eingeben.')),
      );
      return;
    }

    Navigator.pop(
      context,
      _ProjectDraft(
        title: title,
        description: _description.text.trim(),
        location: _location.text.trim(),
        status: _status,
        startDate: _startDate,
        endDate: _endDate,
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
            Text(
              widget.project == null ? 'Neues Projekt' : 'Projekt bearbeiten',
              style: const TextStyle(
                color: Color(0xFF0A1F44),
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Projektname *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Beschreibung / Notizen',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: 'Ort',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'planung',
                  child: Text('Planung'),
                ),
                DropdownMenuItem(
                  value: 'aktiv',
                  child: Text('Aktiv'),
                ),
                DropdownMenuItem(
                  value: 'pausiert',
                  child: Text('Pausiert'),
                ),
                DropdownMenuItem(
                  value: 'abgeschlossen',
                  child: Text('Abgeschlossen'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _status = value);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickStart,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('Start: ${_dateLabel(_startDate)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickEnd,
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text('Ende: ${_dateLabel(_endDate)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _ProjectToolTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ProjectToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE3E8EE)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0A1F44),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF98A2B3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskDraft {
  final String title;
  final String description;
  final String? assignedTo;
  final DateTime? dueDate;
  final DateTime? dueAt;
  final bool reminderEnabled;
  final int reminderMinutes;
  final String status;
  final String priority;

  const _TaskDraft({
    required this.title,
    required this.description,
    required this.assignedTo,
    required this.dueDate,
    required this.dueAt,
    required this.reminderEnabled,
    required this.reminderMinutes,
    required this.status,
    required this.priority,
  });
}

class _TaskEditorSheet extends StatefulWidget {
  final List<Map<String, dynamic>> trainers;
  final Map<String, dynamic>? task;

  const _TaskEditorSheet({
    required this.trainers,
    this.task,
  });

  @override
  State<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<_TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;

  String? _assignedTo;
  DateTime? _dueDate;
  TimeOfDay _dueTime = const TimeOfDay(hour: 18, minute: 0);
  bool _reminderEnabled = true;
  int _reminderMinutes = 1440;
  String _status = 'offen';
  String _priority = 'normal';

  @override
  void initState() {
    super.initState();

    final task = widget.task;

    _title = TextEditingController(
      text: task?['title']?.toString() ?? '',
    );

    _description = TextEditingController(
      text: task?['description']?.toString() ?? '',
    );

    _assignedTo = task?['assigned_to']?.toString();
    _status = task?['status']?.toString() ?? 'offen';
    _priority = task?['priority']?.toString() ?? 'normal';
    _reminderEnabled = task?['reminder_enabled'] != false;
    _reminderMinutes =
        (task?['reminder_minutes'] as num?)?.toInt() ?? 1440;

    final dueAt =
        DateTime.tryParse(task?['due_at']?.toString() ?? '')?.toLocal();

    if (dueAt != null) {
      _dueDate = DateTime(dueAt.year, dueAt.month, dueAt.day);
      _dueTime = TimeOfDay(hour: dueAt.hour, minute: dueAt.minute);
    } else {
      _dueDate = DateTime.tryParse(task?['due_date']?.toString() ?? '');

      if (_dueDate != null) {
        _dueTime = const TimeOfDay(hour: 18, minute: 0);
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  String _trainerName(Map<String, dynamic> trainer) {
    final first = trainer['first_name']?.toString().trim() ?? '';
    final last = trainer['last_name']?.toString().trim() ?? '';

    final value = '$first $last'.trim();
    return value.isEmpty ? 'Ausbilder' : value;
  }

  String _dateLabel() {
    final date = _dueDate;
    if (date == null) return 'Kein Fälligkeitsdatum';

    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  Future<void> _pickDueDate() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );

    if (result != null) {
      setState(() {
        _dueDate = result;
        _reminderEnabled = true;
      });
    }
  }

  Future<void> _pickDueTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime: _dueTime,
    );

    if (result != null) {
      setState(() => _dueTime = result);
    }
  }

  DateTime? _combinedDueAt() {
    final date = _dueDate;
    if (date == null) return null;

    return DateTime(
      date.year,
      date.month,
      date.day,
      _dueTime.hour,
      _dueTime.minute,
    );
  }

  void _save() {
    final title = _title.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte eine Aufgabe eingeben.'),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      _TaskDraft(
        title: title,
        description: _description.text.trim(),
        assignedTo: _assignedTo,
        dueDate: _dueDate,
        dueAt: _combinedDueAt(),
        reminderEnabled: _dueDate != null && _reminderEnabled,
        reminderMinutes: _reminderMinutes,
        status: _status,
        priority: _priority,
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
            Text(
              widget.task == null ? 'Neue Aufgabe' : 'Aufgabe bearbeiten',
              style: const TextStyle(
                color: Color(0xFF0A1F44),
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Aufgabe *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Beschreibung',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _assignedTo,
              decoration: const InputDecoration(
                labelText: 'Verantwortlicher Ausbilder',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Nicht zugewiesen'),
                ),
                ...widget.trainers.map(
                  (trainer) => DropdownMenuItem<String?>(
                    value: trainer['id']?.toString(),
                    child: Text(_trainerName(trainer)),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _assignedTo = value);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'offen',
                        child: Text('Offen'),
                      ),
                      DropdownMenuItem(
                        value: 'in_arbeit',
                        child: Text('In Arbeit'),
                      ),
                      DropdownMenuItem(
                        value: 'erledigt',
                        child: Text('Erledigt'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _status = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(
                      labelText: 'Priorität',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'niedrig',
                        child: Text('Niedrig'),
                      ),
                      DropdownMenuItem(
                        value: 'normal',
                        child: Text('Normal'),
                      ),
                      DropdownMenuItem(
                        value: 'hoch',
                        child: Text('Hoch'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _priority = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickDueDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(_dateLabel()),
              ),
            ),
            if (_dueDate != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickDueTime,
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(
                    'Fällig um ${_dueTime.format(context)} Uhr',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Automatisch erinnern',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: const Text(
                  'Der verantwortliche Ausbilder erhält eine Push-Erinnerung.',
                ),
                value: _reminderEnabled,
                onChanged: (value) {
                  setState(() => _reminderEnabled = value);
                },
              ),
              if (_reminderEnabled)
                DropdownButtonFormField<int>(
                  initialValue: _reminderMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Erinnerung',
                    prefixIcon: Icon(Icons.notifications_active_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 15,
                      child: Text('15 Minuten vorher'),
                    ),
                    DropdownMenuItem(
                      value: 30,
                      child: Text('30 Minuten vorher'),
                    ),
                    DropdownMenuItem(
                      value: 60,
                      child: Text('1 Stunde vorher'),
                    ),
                    DropdownMenuItem(
                      value: 120,
                      child: Text('2 Stunden vorher'),
                    ),
                    DropdownMenuItem(
                      value: 180,
                      child: Text('3 Stunden vorher'),
                    ),
                    DropdownMenuItem(
                      value: 1440,
                      child: Text('1 Tag vorher'),
                    ),
                    DropdownMenuItem(
                      value: 2880,
                      child: Text('2 Tage vorher'),
                    ),
                    DropdownMenuItem(
                      value: 10080,
                      child: Text('1 Woche vorher'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _reminderMinutes = value);
                    }
                  },
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _dueDate = null;
                      _reminderEnabled = false;
                    });
                  },
                  child: const Text('Fälligkeit entfernen'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectChecklistScreen extends StatefulWidget {
  final String projectId;
  final String projectTitle;

  const _ProjectChecklistScreen({
    required this.projectId,
    required this.projectTitle,
  });

  @override
  State<_ProjectChecklistScreen> createState() =>
      _ProjectChecklistScreenState();
}

class _ProjectChecklistScreenState extends State<_ProjectChecklistScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _green = Color(0xFF13A05B);
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _supabase
          .from('project_checklist_items')
          .select()
          .eq('project_id', widget.projectId)
          .order('sort_order')
          .order('created_at');

      if (!mounted) return;

      setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Checkliste konnte nicht geladen werden: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _add() async {
    final controller = TextEditingController();

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Checklistenpunkt'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Was muss erledigt werden?',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            final text = controller.text.trim();
            if (text.isNotEmpty) Navigator.pop(dialogContext, text);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(dialogContext, text);
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (value == null || value.trim().isEmpty) return;

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('project_checklist_items').insert({
        'project_id': widget.projectId,
        'title': value.trim(),
        'sort_order': _items.length,
        'created_by': user.id,
      });
      await _load();
    } catch (e) {
      _showError('Punkt konnte nicht angelegt werden: $e');
    }
  }

  Future<void> _toggle(Map<String, dynamic> item, bool value) async {
    try {
      await _supabase
          .from('project_checklist_items')
          .update({'is_done': value})
          .eq('id', item['id']);
      await _load();
    } catch (e) {
      _showError('Punkt konnte nicht geändert werden: $e');
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    try {
      await _supabase
          .from('project_checklist_items')
          .delete()
          .eq('id', item['id']);
      await _load();
    } catch (e) {
      _showError('Punkt konnte nicht gelöscht werden: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _items.where((item) => item['is_done'] == true).length;
    final progress = _items.isEmpty ? 0.0 : done / _items.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: const Text('Checkliste'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Punkt'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.projectTitle,
              style: const TextStyle(
                color: _navy,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE3E8EE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_items.isEmpty ? 0 : done} von ${_items.length} erledigt',
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 9),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    color: _green,
                    backgroundColor: const Color(0xFFE9EEF4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_items.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.checklist_outlined),
                  title: Text('Noch keine Checklistenpunkte'),
                  subtitle: Text('Über „Punkt“ kannst du den ersten anlegen.'),
                ),
              )
            else
              ..._items.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: CheckboxListTile(
                    value: item['is_done'] == true,
                    onChanged: (value) => _toggle(item, value ?? false),
                    title: Text(
                      item['title']?.toString() ?? 'Punkt',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: item['is_done'] == true
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    secondary: IconButton(
                      tooltip: 'Löschen',
                      onPressed: () => _delete(item),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProjectMaterialsScreen extends StatefulWidget {
  final String projectId;
  final String projectTitle;

  const _ProjectMaterialsScreen({
    required this.projectId,
    required this.projectTitle,
  });

  @override
  State<_ProjectMaterialsScreen> createState() =>
      _ProjectMaterialsScreenState();
}

class _ProjectMaterialsScreenState extends State<_ProjectMaterialsScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _orange = Color(0xFFFF7A00);
  static const _green = Color(0xFF13A05B);

  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _materials = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _supabase
          .from('project_materials')
          .select()
          .eq('project_id', widget.projectId)
          .order('created_at');

      if (!mounted) return;

      setState(() {
        _materials = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Material konnte nicht geladen werden: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double get _plannedTotal {
    return _materials.fold<double>(
      0,
      (sum, item) =>
          sum +
          _number(item['quantity']) * _number(item['planned_unit_cost']),
    );
  }

  double get _actualTotal {
    return _materials.fold<double>(
      0,
      (sum, item) => sum + _number(item['actual_cost']),
    );
  }

  String _money(double value) {
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  Future<void> _edit([Map<String, dynamic>? material]) async {
    final draft = await showModalBottomSheet<_MaterialDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MaterialEditorSheet(material: material),
    );

    if (draft == null) return;

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final payload = {
      'project_id': widget.projectId,
      'name': draft.name,
      'quantity': draft.quantity,
      'unit': draft.unit.isEmpty ? null : draft.unit,
      'planned_unit_cost': draft.plannedUnitCost,
      'actual_cost': draft.actualCost,
      'status': draft.status,
      'notes': draft.notes.isEmpty ? null : draft.notes,
    };

    try {
      if (material == null) {
        await _supabase.from('project_materials').insert({
          ...payload,
          'created_by': user.id,
        });
      } else {
        await _supabase
            .from('project_materials')
            .update(payload)
            .eq('id', material['id']);
      }

      await _load();
    } catch (e) {
      _showError('Material konnte nicht gespeichert werden: $e');
    }
  }

  Future<void> _delete(Map<String, dynamic> material) async {
    try {
      await _supabase
          .from('project_materials')
          .delete()
          .eq('id', material['id']);
      await _load();
    } catch (e) {
      _showError('Material konnte nicht gelöscht werden: $e');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'gekauft':
        return _green;
      case 'bestellt':
        return const Color(0xFF0B4EA2);
      default:
        return _orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'gekauft':
        return 'Gekauft';
      case 'bestellt':
        return 'Bestellt';
      default:
        return 'Geplant';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: const Text('Material & Kosten'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Material'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.projectTitle,
              style: const TextStyle(
                color: _navy,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CostBox(
                    label: 'Geplant',
                    value: _money(_plannedTotal),
                    icon: Icons.calculate_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CostBox(
                    label: 'Tatsächlich',
                    value: _money(_actualTotal),
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_materials.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Noch kein Material geplant'),
                ),
              )
            else
              ..._materials.map((item) {
                final quantity = _number(item['quantity']);
                final unitCost = _number(item['planned_unit_cost']);
                final planned = quantity * unitCost;
                final status = item['status']?.toString() ?? 'geplant';
                final actual = item['actual_cost'];

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    leading: CircleAvatar(
                      backgroundColor:
                          _statusColor(status).withValues(alpha: 0.12),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: _statusColor(status),
                      ),
                    ),
                    title: Text(
                      item['name']?.toString() ?? 'Material',
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2)} '
                            '${item['unit'] ?? ''} · geplant ${_money(planned)}',
                          ),
                          if (actual != null)
                            Text('tatsächlich ${_money(_number(actual))}'),
                          const SizedBox(height: 4),
                          Text(
                            _statusLabel(status),
                            style: TextStyle(
                              color: _statusColor(status),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _edit(item);
                        } else if (value == 'delete') {
                          _delete(item);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Bearbeiten'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Löschen'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _CostBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _CostBox({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E8EE)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF0B4EA2)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0A1F44),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaterialDraft {
  final String name;
  final double quantity;
  final String unit;
  final double plannedUnitCost;
  final double? actualCost;
  final String status;
  final String notes;

  const _MaterialDraft({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.plannedUnitCost,
    required this.actualCost,
    required this.status,
    required this.notes,
  });
}

class _MaterialEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? material;

  const _MaterialEditorSheet({
    this.material,
  });

  @override
  State<_MaterialEditorSheet> createState() => _MaterialEditorSheetState();
}

class _MaterialEditorSheetState extends State<_MaterialEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _unit;
  late final TextEditingController _plannedUnitCost;
  late final TextEditingController _actualCost;
  late final TextEditingController _notes;

  String _status = 'geplant';

  @override
  void initState() {
    super.initState();

    final material = widget.material;

    _name = TextEditingController(
      text: material?['name']?.toString() ?? '',
    );
    _quantity = TextEditingController(
      text: material?['quantity']?.toString() ?? '1',
    );
    _unit = TextEditingController(
      text: material?['unit']?.toString() ?? '',
    );
    _plannedUnitCost = TextEditingController(
      text: material?['planned_unit_cost']?.toString() ?? '0',
    );
    _actualCost = TextEditingController(
      text: material?['actual_cost']?.toString() ?? '',
    );
    _notes = TextEditingController(
      text: material?['notes']?.toString() ?? '',
    );
    _status = material?['status']?.toString() ?? 'geplant';
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    _plannedUnitCost.dispose();
    _actualCost.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? _parse(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  void _save() {
    final name = _name.text.trim();
    final quantity = _parse(_quantity.text);
    final unitCost = _parse(_plannedUnitCost.text);
    final actual = _actualCost.text.trim().isEmpty
        ? null
        : _parse(_actualCost.text);

    if (name.isEmpty ||
        quantity == null ||
        quantity <= 0 ||
        unitCost == null ||
        unitCost < 0 ||
        (_actualCost.text.trim().isNotEmpty &&
            (actual == null || actual < 0))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Material und Kosten korrekt eingeben.'),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      _MaterialDraft(
        name: name,
        quantity: quantity,
        unit: _unit.text.trim(),
        plannedUnitCost: unitCost,
        actualCost: actual,
        status: _status,
        notes: _notes.text.trim(),
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
            Text(
              widget.material == null ? 'Material hinzufügen' : 'Material ändern',
              style: const TextStyle(
                color: Color(0xFF0A1F44),
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Material *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Menge',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(
                      labelText: 'Einheit',
                      hintText: 'Stk., m, kg …',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _plannedUnitCost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Geplanter Preis pro Einheit (€)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _actualCost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tatsächliche Gesamtkosten (€)',
                hintText: 'optional',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'geplant',
                  child: Text('Geplant'),
                ),
                DropdownMenuItem(
                  value: 'bestellt',
                  child: Text('Bestellt'),
                ),
                DropdownMenuItem(
                  value: 'gekauft',
                  child: Text('Gekauft'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notizen',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectDocumentsScreen extends StatefulWidget {
  final String projectId;
  final String projectTitle;

  const _ProjectDocumentsScreen({
    required this.projectId,
    required this.projectTitle,
  });

  @override
  State<_ProjectDocumentsScreen> createState() =>
      _ProjectDocumentsScreenState();
}

class _ProjectDocumentsScreenState extends State<_ProjectDocumentsScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _uploading = false;
  List<Map<String, dynamic>> _documents = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _supabase
          .from('project_documents')
          .select()
          .eq('project_id', widget.projectId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _documents = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Dokumente konnten nicht geladen werden: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _mimeType(String fileName) {
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

  IconData _fileIcon(String fileName) {
    final name = fileName.toLowerCase();
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _size(dynamic value) {
    final bytes = (value as num?)?.toInt() ?? 0;
    if (bytes <= 0) return '';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _upload() async {
    if (_uploading) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'jpg',
        'jpeg',
        'png',
        'webp',
        'txt',
        'doc',
        'docx',
        'xls',
        'xlsx',
      ],
    );

    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final bytes = picked.bytes;

    if (bytes == null || bytes.isEmpty) {
      _showError('Die Datei konnte nicht gelesen werden.');
      return;
    }

    if (picked.size > 25 * 1024 * 1024) {
      _showError('Die Datei ist größer als 25 MB.');
      return;
    }

    final titleController = TextEditingController(
      text: picked.name.contains('.')
          ? picked.name.substring(0, picked.name.lastIndexOf('.'))
          : picked.name,
    );

    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Projektdokument'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Titel',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final value = titleController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Hochladen'),
          ),
        ],
      ),
    );

    titleController.dispose();

    if (title == null || title.isEmpty) return;

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _uploading = true);

    String? storagePath;

    try {
      final safeName = picked.name.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );

      storagePath =
          '${widget.projectId}/${DateTime.now().millisecondsSinceEpoch}_$safeName';

      await _supabase.storage.from('project-documents').uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _mimeType(picked.name),
              upsert: false,
            ),
          );

      await _supabase.from('project_documents').insert({
        'project_id': widget.projectId,
        'title': title,
        'file_name': picked.name,
        'storage_path': storagePath,
        'mime_type': _mimeType(picked.name),
        'size_bytes': picked.size,
        'uploaded_by': user.id,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Projektdokument hochgeladen.')),
      );

      await _load();
    } catch (e) {
      if (storagePath != null) {
        try {
          await _supabase.storage
              .from('project-documents')
              .remove([storagePath]);
        } catch (_) {}
      }

      _showError('Upload fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> document) async {
    try {
      final path = document['storage_path']?.toString() ?? '';
      if (path.isEmpty) throw Exception('Kein Speicherpfad vorhanden.');

      final signedUrl = await _supabase.storage
          .from('project-documents')
          .createSignedUrl(path, 120);

      final opened = await launchUrl(
        Uri.parse(signedUrl),
        mode: LaunchMode.platformDefault,
      );

      if (!opened) {
        throw Exception('Datei konnte nicht geöffnet werden.');
      }
    } catch (e) {
      _showError('Dokument konnte nicht geöffnet werden: $e');
    }
  }

  Future<void> _delete(Map<String, dynamic> document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dokument löschen?'),
        content: Text(
          '„${document['title'] ?? document['file_name'] ?? 'Dokument'}“ '
          'wird dauerhaft gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final path = document['storage_path']?.toString() ?? '';

      if (path.isNotEmpty) {
        await _supabase.storage
            .from('project-documents')
            .remove([path]);
      }

      await _supabase
          .from('project_documents')
          .delete()
          .eq('id', document['id']);

      await _load();
    } catch (e) {
      _showError('Dokument konnte nicht gelöscht werden: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: const Text('Projektdokumente'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _upload,
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.upload_file),
        label: const Text('Dokument'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.projectTitle,
              style: const TextStyle(
                color: _navy,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Diese Dateien sind ausschließlich für Ausbilder zugänglich.',
              style: TextStyle(color: Color(0xFF667085)),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_documents.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.folder_open_outlined),
                  title: Text('Noch keine Projektdokumente'),
                ),
              )
            else
              ..._documents.map(
                (document) => Card(
                  margin: const EdgeInsets.only(bottom: 9),
                  child: ListTile(
                    onTap: () => _open(document),
                    leading: CircleAvatar(
                      backgroundColor: _blue.withValues(alpha: 0.12),
                      child: Icon(
                        _fileIcon(document['file_name']?.toString() ?? ''),
                        color: _blue,
                      ),
                    ),
                    title: Text(
                      document['title']?.toString() ?? 'Dokument',
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      [
                        document['file_name']?.toString() ?? '',
                        _size(document['size_bytes']),
                      ].where((value) => value.isNotEmpty).join(' · '),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'open') {
                          _open(document);
                        } else if (value == 'delete') {
                          _delete(document);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'open',
                          child: Text('Öffnen'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Löschen'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
