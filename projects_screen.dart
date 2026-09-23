import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          .order('due_date', ascending: true)
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
                                  if ((task['due_date']?.toString() ?? '')
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.event_outlined,
                                          size: 17,
                                          color: Color(0xFF667085),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Fällig: '
                                          '${_formatDate(task['due_date'])}',
                                          style: const TextStyle(
                                            color: Color(0xFF667085),
                                          ),
                                        ),
                                      ],
                                    ),
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

class _TaskDraft {
  final String title;
  final String description;
  final String? assignedTo;
  final DateTime? dueDate;
  final String status;
  final String priority;

  const _TaskDraft({
    required this.title,
    required this.description,
    required this.assignedTo,
    required this.dueDate,
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
    _dueDate = DateTime.tryParse(task?['due_date']?.toString() ?? '');
    _status = task?['status']?.toString() ?? 'offen';
    _priority = task?['priority']?.toString() ?? 'normal';
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
    if (date == null) return 'Keine Fälligkeit';

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
      setState(() => _dueDate = result);
    }
  }

  void _save() {
    final title = _title.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte eine Aufgabe eingeben.')),
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
            if (_dueDate != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _dueDate = null),
                  child: const Text('Fälligkeit entfernen'),
                ),
              ),
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
