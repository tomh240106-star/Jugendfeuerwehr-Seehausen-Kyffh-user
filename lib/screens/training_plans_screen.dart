import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TrainingPlansScreen extends StatefulWidget {
  const TrainingPlansScreen({super.key});

  @override
  State<TrainingPlansScreen> createState() => _TrainingPlansScreenState();
}

class _TrainingPlansScreenState extends State<TrainingPlansScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  String? _error;
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadRole(),
      _loadPlans(),
    ]);
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
          .order('valid_from', ascending: false);

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

  String _date(dynamic value) {
    if (value == null || value.toString().isEmpty) return '–';
    final dt = DateTime.tryParse(value.toString());
    if (dt == null) return value.toString();
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  Future<void> _openPlanEditor({Map<String, dynamic>? plan}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TrainingPlanEditor(plan: plan),
    );

    if (changed == true) {
      await _loadPlans();
    }
  }

  Future<void> _deletePlan(Map<String, dynamic> plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ausbildungsplan löschen?'),
        content: Text(
          '„${plan['title'] ?? 'Ausbildungsplan'}“ wird vollständig gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
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
            'body': '${plan['title'] ?? 'Ausbildungsplan'} wurde entfernt.',
          },
        );
      } catch (pushError) {
        debugPrint('Ausbildungsplan gelöscht, Push fehlgeschlagen: $pushError');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ausbildungsplan gelöscht')),
      );
      await _loadPlans();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A1F44);
    const blue = Color(0xFF0B4EA2);
    const red = Color(0xFFE30613);
    const orange = Color(0xFFFF7A00);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F5F7),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 70, color: red),
                  const SizedBox(height: 16),
                  const Text(
                    'Ausbildungspläne konnten nicht geladen werden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _loadPlans,
                    icon: const Icon(Icons.refresh),
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
      backgroundColor: const Color(0xFFF3F5F7),
      body: RefreshIndicator(
        onRefresh: _loadPlans,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
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
                              'Ausbildung',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Pläne, Themen und Lernziele',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isTrainer)
                        IconButton(
                          tooltip: 'Ausbildungsplan erstellen',
                          onPressed: () => _openPlanEditor(),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: red,
                          ),
                          icon: const Icon(Icons.add),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
              child: _plans.isEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 54,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFE3E8EE)),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 72,
                            color: orange,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Noch keine Ausbildungspläne vorhanden.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: navy,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: _plans.map((plan) {
                        final description =
                            plan['description']?.toString().trim() ?? '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
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
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              Navigator.of(context)
                                  .push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          TrainingPlanDetailsScreen(
                                        plan: plan,
                                        isTrainer: _isTrainer,
                                      ),
                                    ),
                                  )
                                  .then((_) => _loadPlans());
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF0E0),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.school_outlined,
                                      color: orange,
                                      size: 29,
                                    ),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          plan['title']?.toString() ??
                                              'Ausbildungsplan',
                                          style: const TextStyle(
                                            color: navy,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        if (description.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF667085),
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.date_range_outlined,
                                              size: 17,
                                              color: Color(0xFF98A2B3),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                '${_date(plan['valid_from'])} – ${_date(plan['valid_until'])}',
                                                style: const TextStyle(
                                                  color: Color(0xFF667085),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (_isTrainer) ...[
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              OutlinedButton.icon(
                                                onPressed: () =>
                                                    _openPlanEditor(plan: plan),
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18,
                                                ),
                                                label:
                                                    const Text('Bearbeiten'),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                tooltip: 'Löschen',
                                                onPressed: () =>
                                                    _deletePlan(plan),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: red,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
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
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isTrainer
          ? FloatingActionButton(
              onPressed: () => _openPlanEditor(),
              backgroundColor: red,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

}

class TrainingPlanDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> plan;
  final bool isTrainer;

  const TrainingPlanDetailsScreen({
    super.key,
    required this.plan,
    required this.isTrainer,
  });

  @override
  State<TrainingPlanDetailsScreen> createState() =>
      _TrainingPlanDetailsScreenState();
}

class _TrainingPlanDetailsScreenState
    extends State<TrainingPlanDetailsScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _units = [];

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final rows = await _supabase
          .from('training_units')
          .select()
          .eq('training_plan_id', widget.plan['id'])
          .order('sort_order', ascending: true);

      if (!mounted) return;
      setState(() {
        _units = List<Map<String, dynamic>>.from(rows);
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

  Future<void> _openUnitEditor({Map<String, dynamic>? unit}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TrainingUnitEditor(
        trainingPlanId: widget.plan['id'].toString(),
        unit: unit,
        suggestedOrder: unit == null ? _units.length + 1 : null,
      ),
    );

    if (changed == true) {
      await _loadUnits();
    }
  }

  Future<void> _deleteUnit(Map<String, dynamic> unit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ausbildungseinheit löschen?'),
        content: Text(
          '„${unit['title'] ?? 'Einheit'}“ wird gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _supabase
        .from('training_units')
        .delete()
        .eq('id', unit['id']);

    try {
      await _supabase.functions.invoke(
        'send-push',
        body: {
          'title': 'Ausbildungseinheit gelöscht',
          'body': '${unit['title'] ?? 'Ausbildungseinheit'} wurde entfernt.',
        },
      );
    } catch (pushError) {
      debugPrint('Ausbildungseinheit gelöscht, Push fehlgeschlagen: $pushError');
    }

    if (!mounted) return;
    await _loadUnits();
  }

  Widget _detail(String label, dynamic value, IconData icon) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFFE30613)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A1F44);
    const blue = Color(0xFF0B4EA2);
    const red = Color(0xFFE30613);
    const orange = Color(0xFFFF7A00);

    final title = widget.plan['title']?.toString() ?? 'Ausbildungsplan';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: _loading
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
              : RefreshIndicator(
                  onRefresh: _loadUnits,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if ((widget.plan['description'] ?? '')
                          .toString()
                          .isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFE3E8EE),
                            ),
                          ),
                          child: Text(
                            widget.plan['description'].toString(),
                            style: const TextStyle(
                              color: Color(0xFF475467),
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Ausbildungseinheiten',
                              style: TextStyle(
                                color: navy,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF2FB),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_units.length}',
                              style: const TextStyle(
                                color: blue,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_units.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFE3E8EE),
                            ),
                          ),
                          child: const Text(
                            'Noch keine Ausbildungseinheiten angelegt.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF667085),
                            ),
                          ),
                        ),
                      ..._units.map((unit) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFE3E8EE),
                            ),
                          ),
                          child: ExpansionTile(
                            shape: const Border(),
                            collapsedShape: const Border(),
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFFFF0E0),
                              foregroundColor: orange,
                              child: Text(
                                (unit['sort_order'] ?? 0).toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            title: Text(
                              unit['title']?.toString() ?? 'Einheit',
                              style: const TextStyle(
                                color: navy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: (unit['topic'] ?? '')
                                    .toString()
                                    .isEmpty
                                ? null
                                : Text(
                                    unit['topic'].toString(),
                                    style: const TextStyle(
                                      color: Color(0xFF667085),
                                    ),
                                  ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            children: [
                              _detail(
                                'Lernziel',
                                unit['objectives'],
                                Icons.flag_outlined,
                              ),
                              _detail(
                                'Dauer',
                                unit['duration_minutes'] == null
                                    ? null
                                    : '${unit['duration_minutes']} Minuten',
                                Icons.schedule,
                              ),
                              _detail(
                                'Material',
                                unit['equipment'],
                                Icons.construction_outlined,
                              ),
                              _detail(
                                'Inhalt',
                                unit['content'],
                                Icons.notes,
                              ),
                              if (widget.isTrainer) ...[
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _openUnitEditor(unit: unit),
                                      icon: const Icon(Icons.edit),
                                      label: const Text('Bearbeiten'),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'Löschen',
                                      onPressed: () => _deleteUnit(unit),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: red,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 90),
                    ],
                  ),
                ),
      floatingActionButton: widget.isTrainer
          ? FloatingActionButton(
              onPressed: () => _openUnitEditor(),
              backgroundColor: red,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

}

class _TrainingPlanEditor extends StatefulWidget {
  final Map<String, dynamic>? plan;

  const _TrainingPlanEditor({this.plan});

  @override
  State<_TrainingPlanEditor> createState() => _TrainingPlanEditorState();
}

class _TrainingPlanEditorState extends State<_TrainingPlanEditor> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _title;
  late final TextEditingController _description;
  DateTime? _validFrom;
  DateTime? _validUntil;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: widget.plan?['title']?.toString() ?? '',
    );
    _description = TextEditingController(
      text: widget.plan?['description']?.toString() ?? '',
    );
    _validFrom = DateTime.tryParse(
      widget.plan?['valid_from']?.toString() ?? '',
    );
    _validUntil = DateTime.tryParse(
      widget.plan?['valid_until']?.toString() ?? '',
    );
  }

  String _isoDate(DateTime? date) {
    if (date == null) return '';
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _displayDate(DateTime? date) {
    if (date == null) return 'Nicht gesetzt';
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Future<void> _pickDate(bool from) async {
    final current = from ? _validFrom : _validUntil;

    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      if (from) {
        _validFrom = picked;
      } else {
        _validUntil = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_validFrom != null &&
        _validUntil != null &&
        _validUntil!.isBefore(_validFrom!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Enddatum liegt vor dem Startdatum.'),
        ),
      );
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    final data = {
      'title': _title.text.trim(),
      'description': _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      'valid_from': _validFrom == null ? null : _isoDate(_validFrom),
      'valid_until': _validUntil == null ? null : _isoDate(_validUntil),
    };

    try {
      if (widget.plan == null) {
        await _supabase.from('training_plans').insert({
          ...data,
          'created_by': user.id,
        });

        try {
          await _supabase.functions.invoke(
            'send-push',
            body: {
              'title': 'Neuer Ausbildungsplan',
              'body': _title.text.trim(),
            },
          );
        } catch (pushError) {
          debugPrint('Ausbildungsplan gespeichert, Push fehlgeschlagen: $pushError');
        }
      } else {
        await _supabase
            .from('training_plans')
            .update(data)
            .eq('id', widget.plan!['id']);

        try {
          await _supabase.functions.invoke(
            'send-push',
            body: {
              'title': 'Ausbildungsplan geändert',
              'body': _title.text.trim(),
            },
          );
        } catch (pushError) {
          debugPrint('Ausbildungsplan geändert, Push fehlgeschlagen: $pushError');
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
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
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.plan == null
                    ? 'Ausbildungsplan erstellen'
                    : 'Ausbildungsplan bearbeiten',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Titel *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Bitte einen Titel eingeben.'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Beschreibung',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range),
                title: const Text('Gültig ab'),
                subtitle: Text(_displayDate(_validFrom)),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () => _pickDate(true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available),
                title: const Text('Gültig bis'),
                subtitle: Text(_displayDate(_validUntil)),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () => _pickDate(false),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    widget.plan == null ? 'Erstellen' : 'Speichern',
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

class _TrainingUnitEditor extends StatefulWidget {
  final String trainingPlanId;
  final Map<String, dynamic>? unit;
  final int? suggestedOrder;

  const _TrainingUnitEditor({
    required this.trainingPlanId,
    this.unit,
    this.suggestedOrder,
  });

  @override
  State<_TrainingUnitEditor> createState() => _TrainingUnitEditorState();
}

class _TrainingUnitEditorState extends State<_TrainingUnitEditor> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _title;
  late final TextEditingController _topic;
  late final TextEditingController _objectives;
  late final TextEditingController _duration;
  late final TextEditingController _equipment;
  late final TextEditingController _content;
  late final TextEditingController _sortOrder;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: widget.unit?['title']?.toString() ?? '',
    );
    _topic = TextEditingController(
      text: widget.unit?['topic']?.toString() ?? '',
    );
    _objectives = TextEditingController(
      text: widget.unit?['objectives']?.toString() ?? '',
    );
    _duration = TextEditingController(
      text: widget.unit?['duration_minutes']?.toString() ?? '',
    );
    _equipment = TextEditingController(
      text: widget.unit?['equipment']?.toString() ?? '',
    );
    _content = TextEditingController(
      text: widget.unit?['content']?.toString() ?? '',
    );
    _sortOrder = TextEditingController(
      text: widget.unit?['sort_order']?.toString() ??
          (widget.suggestedOrder ?? 0).toString(),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final durationText = _duration.text.trim();
    final duration = durationText.isEmpty ? null : int.tryParse(durationText);
    if (durationText.isNotEmpty && (duration == null || duration <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Dauer muss eine Zahl größer als 0 sein.'),
        ),
      );
      return;
    }

    final sortOrder = int.tryParse(_sortOrder.text.trim());
    if (sortOrder == null || sortOrder < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Reihenfolge muss 0 oder größer sein.'),
        ),
      );
      return;
    }

    final data = {
      'training_plan_id': widget.trainingPlanId,
      'title': _title.text.trim(),
      'topic': _topic.text.trim().isEmpty ? null : _topic.text.trim(),
      'objectives':
          _objectives.text.trim().isEmpty ? null : _objectives.text.trim(),
      'duration_minutes': duration,
      'equipment':
          _equipment.text.trim().isEmpty ? null : _equipment.text.trim(),
      'content': _content.text.trim().isEmpty ? null : _content.text.trim(),
      'sort_order': sortOrder,
    };

    setState(() => _saving = true);

    try {
      if (widget.unit == null) {
        await _supabase.from('training_units').insert(data);

        try {
          await _supabase.functions.invoke(
            'send-push',
            body: {
              'title': 'Neue Ausbildungseinheit',
              'body': _title.text.trim(),
            },
          );
        } catch (pushError) {
          debugPrint('Ausbildungseinheit gespeichert, Push fehlgeschlagen: $pushError');
        }
      } else {
        await _supabase
            .from('training_units')
            .update(data)
            .eq('id', widget.unit!['id']);

        try {
          await _supabase.functions.invoke(
            'send-push',
            body: {
              'title': 'Ausbildungseinheit geändert',
              'body': _title.text.trim(),
            },
          );
        } catch (pushError) {
          debugPrint('Ausbildungseinheit geändert, Push fehlgeschlagen: $pushError');
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _topic.dispose();
    _objectives.dispose();
    _duration.dispose();
    _equipment.dispose();
    _content.dispose();
    _sortOrder.dispose();
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
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.unit == null
                    ? 'Ausbildungseinheit erstellen'
                    : 'Ausbildungseinheit bearbeiten',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Titel *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Bitte einen Titel eingeben.'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _topic,
                decoration: const InputDecoration(
                  labelText: 'Thema',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _objectives,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Lernziele',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _duration,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Dauer (Min.)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _sortOrder,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Reihenfolge',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _equipment,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Benötigtes Material',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _content,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Ausbildungsinhalt / Ablauf',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    widget.unit == null ? 'Erstellen' : 'Speichern',
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
