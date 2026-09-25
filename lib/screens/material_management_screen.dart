import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/home_navigation.dart';

class MaterialManagementScreen extends StatefulWidget {
  const MaterialManagementScreen({super.key});

  @override
  State<MaterialManagementScreen> createState() =>
      _MaterialManagementScreenState();
}

class _MaterialManagementScreenState extends State<MaterialManagementScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);
  static const _orange = Color(0xFFFF7A00);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  String? _error;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _youth = [];

  String _query = '';
  String _category = 'alle';
  bool _onlyProblems = false;

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
      if (user == null) throw Exception('Kein Benutzer angemeldet.');

      final profile = await _supabase
          .from('profiles')
          .select('role,approval_status')
          .eq('id', user.id)
          .maybeSingle();

      final trainer =
          profile?['role']?.toString() == 'ausbilder' &&
          profile?['approval_status']?.toString() == 'approved';

      if (!trainer) {
        if (!mounted) return;
        setState(() {
          _isTrainer = false;
          _loading = false;
        });
        return;
      }

      final result = await Future.wait([
        _supabase
            .from('material_items')
            .select()
            .order('category')
            .order('name'),
        _supabase
            .from('material_assignments')
            .select()
            .order('issued_at', ascending: false),
        _supabase
            .from('profiles')
            .select('id,first_name,last_name,role,approval_status')
            .eq('role', 'jugendmitglied')
            .eq('approval_status', 'approved')
            .order('last_name')
            .order('first_name'),
      ]);

      if (!mounted) return;

      setState(() {
        _isTrainer = true;
        _items = List<Map<String, dynamic>>.from(result[0]);
        _assignments = List<Map<String, dynamic>>.from(result[1]);
        _youth = List<Map<String, dynamic>>.from(result[2]);
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

  int _int(dynamic value) => (value as num?)?.toInt() ?? 0;

  int _activeAssignedQuantity(String materialId) {
    var total = 0;

    for (final row in _assignments) {
      if (row['material_id']?.toString() != materialId) continue;
      if (row['returned_at'] != null) continue;
      total += _int(row['quantity']);
    }

    return total;
  }

  int _available(Map<String, dynamic> item) {
    final total = _int(item['total_quantity']);
    final defective = _int(item['defective_quantity']);
    final assigned = _activeAssignedQuantity(item['id'].toString());

    final value = total - defective - assigned;
    return value < 0 ? 0 : value;
  }

  bool _isProblem(Map<String, dynamic> item) {
    final defective = _int(item['defective_quantity']);
    final minimum = _int(item['minimum_available']);
    final available = _available(item);

    return defective > 0 || available <= minimum;
  }

  int get _totalQuantity =>
      _items.fold<int>(0, (sum, item) => sum + _int(item['total_quantity']));

  int get _assignedQuantity => _assignments
      .where((row) => row['returned_at'] == null)
      .fold<int>(0, (sum, row) => sum + _int(row['quantity']));

  int get _defectiveQuantity =>
      _items.fold<int>(0, (sum, item) => sum + _int(item['defective_quantity']));

  int get _problemCount => _items.where(_isProblem).length;

  List<Map<String, dynamic>> get _filteredItems {
    final q = _query.trim().toLowerCase();

    return _items.where((item) {
      final matchesCategory =
          _category == 'alle' || item['category']?.toString() == _category;

      final haystack = [
        item['name'],
        item['inventory_number'],
        item['size'],
        item['storage_location'],
        item['notes'],
        _categoryLabel(item['category']?.toString() ?? ''),
      ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');

      final matchesQuery = q.isEmpty || haystack.contains(q);
      final matchesProblem = !_onlyProblems || _isProblem(item);

      return matchesCategory && matchesQuery && matchesProblem;
    }).toList();
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'schutzkleidung':
        return 'Schutzkleidung';
      case 'helm':
        return 'Helm';
      case 'handschuhe':
        return 'Handschuhe';
      case 'funk':
        return 'Funk';
      case 'geraet':
        return 'Gerät';
      default:
        return 'Sonstiges';
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'schutzkleidung':
        return Icons.checkroom_outlined;
      case 'helm':
        return Icons.health_and_safety_outlined;
      case 'handschuhe':
        return Icons.back_hand_outlined;
      case 'funk':
        return Icons.radio_outlined;
      case 'geraet':
        return Icons.build_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  String _youthName(String youthId) {
    for (final youth in _youth) {
      if (youth['id']?.toString() != youthId) continue;

      final first = youth['first_name']?.toString().trim() ?? '';
      final last = youth['last_name']?.toString().trim() ?? '';
      final value = '$first $last'.trim();
      return value.isEmpty ? 'Jugendmitglied' : value;
    }

    return 'Jugendmitglied';
  }

  List<Map<String, dynamic>> _activeAssignmentsFor(String materialId) {
    return _assignments
        .where(
          (row) =>
              row['material_id']?.toString() == materialId &&
              row['returned_at'] == null,
        )
        .toList();
  }

  List<Map<String, dynamic>> _allAssignmentsFor(String materialId) {
    return _assignments
        .where((row) => row['material_id']?.toString() == materialId)
        .toList();
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '–';

    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  Future<void> _editItem({Map<String, dynamic>? item}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _MaterialEditor(item: item),
    );

    if (changed == true) {
      await _load();
    }
  }

  Future<void> _assignItem(Map<String, dynamic> item) async {
    final available = _available(item);

    if (available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Von diesem Material ist aktuell nichts verfügbar.'),
        ),
      );
      return;
    }

    final changed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _MaterialAssignmentEditor(
        item: item,
        youth: _youth,
        available: available,
      ),
    );

    if (changed == true) {
      await _load();
    }
  }

  Future<void> _returnAssignment(Map<String, dynamic> assignment) async {
    Map<String, dynamic>? material;
    for (final candidate in _items) {
      if (candidate['id']?.toString() ==
          assignment['material_id']?.toString()) {
        material = candidate;
        break;
      }
    }

    final name = material?['name']?.toString() ?? 'Material';
    final youth = _youthName(assignment['youth_id']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rückgabe bestätigen?'),
        content: Text('$name von $youth als zurückgegeben markieren?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Zurückgeben'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      await _supabase
          .from('material_assignments')
          .update({
            'returned_at': date,
            'updated_by': user.id,
          })
          .eq('id', assignment['id']);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material wurde zurückgegeben.')),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rückgabe fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final active = _activeAssignmentsFor(item['id'].toString());

    if (active.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dieses Material kann nicht gelöscht werden, solange noch Ausgaben offen sind.',
          ),
        ),
      );
      return;
    }

    final history = _allAssignmentsFor(item['id'].toString()).length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Material löschen?'),
        content: Text(
          history == 0
              ? '„${item['name']}“ wird gelöscht.'
              : '„${item['name']}“ wird gelöscht. Dabei wird auch der bisherige Ausgabeverlauf entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _supabase.from('material_items').delete().eq('id', item['id']);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material gelöscht.')),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _showHistory(Map<String, dynamic> item) async {
    final rows = _allAssignmentsFor(item['id'].toString());

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          maxChildSize: 0.95,
          minChildSize: 0.45,
          builder: (_, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                Text(
                  'Ausgabeverlauf – ${item['name']}',
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Für dieses Material gibt es noch keinen Ausgabeverlauf.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ...rows.map((row) {
                    final active = row['returned_at'] == null;
                    final youth =
                        _youthName(row['youth_id']?.toString() ?? '');
                    final note = row['note']?.toString().trim() ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: active
                              ? const Color(0xFFFFF0E0)
                              : const Color(0xFFE8F6EE),
                          child: Icon(
                            active
                                ? Icons.outbox_outlined
                                : Icons.assignment_turned_in_outlined,
                            color: active ? _orange : _green,
                          ),
                        ),
                        title: Text(
                          youth,
                          style: const TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          'Menge: ${_int(row['quantity'])} · '
                          'Ausgabe: ${_date(row['issued_at'])}'
                          '${row['due_back_at'] == null ? '' : ' · Rückgabe geplant: ${_date(row['due_back_at'])}'}'
                          '${row['returned_at'] == null ? '' : ' · Zurück: ${_date(row['returned_at'])}'}'
                          '${note.isEmpty ? '' : '\n$note'}',
                        ),
                        isThreeLine: note.isNotEmpty,
                        trailing: active
                            ? IconButton(
                                tooltip: 'Zurückgeben',
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  _returnAssignment(row);
                                },
                                icon: const Icon(
                                  Icons.keyboard_return,
                                  color: _green,
                                ),
                              )
                            : null,
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F5F7),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isTrainer) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F5F7),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Dieser Bereich ist ausschließlich für Ausbilder freigegeben.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Materialverwaltung'),
        actions: [
          IconButton(
            tooltip: 'Zur Startseite',
            onPressed: () => HomeNavigation.goHome(context),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editItem(),
        backgroundColor: _red,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Material'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_navy, _blue],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.white,
                    size: 34,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bestände, Ausgaben und Rückgaben der Jugendfeuerwehr',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SummaryBox(
                    value: '$_totalQuantity',
                    label: 'Bestand',
                    color: _blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryBox(
                    value: '$_assignedQuantity',
                    label: 'Ausgegeben',
                    color: _orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryBox(
                    value: '$_defectiveQuantity',
                    label: 'Defekt',
                    color: _red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryBox(
                    value: '$_problemCount',
                    label: 'Prüfen',
                    color: _red,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: _red),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Material suchen',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _CategoryChip(
                    label: 'Alle',
                    selected: _category == 'alle',
                    onTap: () => setState(() => _category = 'alle'),
                  ),
                  _CategoryChip(
                    label: 'Schutzkleidung',
                    selected: _category == 'schutzkleidung',
                    onTap: () => setState(() => _category = 'schutzkleidung'),
                  ),
                  _CategoryChip(
                    label: 'Helme',
                    selected: _category == 'helm',
                    onTap: () => setState(() => _category = 'helm'),
                  ),
                  _CategoryChip(
                    label: 'Handschuhe',
                    selected: _category == 'handschuhe',
                    onTap: () => setState(() => _category = 'handschuhe'),
                  ),
                  _CategoryChip(
                    label: 'Funk',
                    selected: _category == 'funk',
                    onTap: () => setState(() => _category = 'funk'),
                  ),
                  _CategoryChip(
                    label: 'Geräte',
                    selected: _category == 'geraet',
                    onTap: () => setState(() => _category = 'geraet'),
                  ),
                  _CategoryChip(
                    label: 'Sonstiges',
                    selected: _category == 'sonstiges',
                    onTap: () => setState(() => _category = 'sonstiges'),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Nur knappe oder defekte Bestände',
                style: TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              value: _onlyProblems,
              onChanged: (value) => setState(() => _onlyProblems = value),
            ),
            const SizedBox(height: 8),
            if (_items.isEmpty)
              const _EmptyBox(
                icon: Icons.inventory_2_outlined,
                text: 'Noch kein Material angelegt.',
              )
            else if (_filteredItems.isEmpty)
              const _EmptyBox(
                icon: Icons.search_off,
                text: 'Kein Material passt zu den gewählten Filtern.',
              )
            else
              ..._filteredItems.map(_buildItemCard),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final materialId = item['id'].toString();
    final assigned = _activeAssignedQuantity(materialId);
    final available = _available(item);
    final defective = _int(item['defective_quantity']);
    final minimum = _int(item['minimum_available']);
    final total = _int(item['total_quantity']);
    final active = _activeAssignmentsFor(materialId);
    final problem = _isProblem(item);

    final inventory = item['inventory_number']?.toString().trim() ?? '';
    final size = item['size']?.toString().trim() ?? '';
    final location = item['storage_location']?.toString().trim() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: problem
              ? _red.withValues(alpha: 0.32)
              : const Color(0xFFE3E8EE),
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            offset: Offset(0, 4),
            color: Color(0x0D000000),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FB),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  _categoryIcon(item['category']?.toString() ?? ''),
                  color: _blue,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name']?.toString() ?? 'Material',
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _categoryLabel(item['category']?.toString() ?? ''),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (problem)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Prüfen',
                    style: TextStyle(
                      color: _red,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(label: 'Gesamt', value: '$total'),
              _InfoPill(label: 'Verfügbar', value: '$available'),
              _InfoPill(label: 'Ausgegeben', value: '$assigned'),
              _InfoPill(label: 'Defekt', value: '$defective'),
              if (minimum > 0)
                _InfoPill(label: 'Mindestbestand', value: '$minimum'),
            ],
          ),
          if (inventory.isNotEmpty || size.isNotEmpty || location.isNotEmpty) ...[
            const SizedBox(height: 11),
            if (inventory.isNotEmpty)
              _LineInfo(
                icon: Icons.qr_code_2_outlined,
                text: 'Inventar-Nr.: $inventory',
              ),
            if (size.isNotEmpty)
              _LineInfo(
                icon: Icons.straighten_outlined,
                text: 'Größe: $size',
              ),
            if (location.isNotEmpty)
              _LineInfo(
                icon: Icons.place_outlined,
                text: 'Lagerort: $location',
              ),
          ],
          if (active.isNotEmpty) ...[
            const Divider(height: 24),
            const Text(
              'Aktuell ausgegeben',
              style: TextStyle(
                color: _navy,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            ...active.take(3).map((row) {
              final youth = _youthName(row['youth_id']?.toString() ?? '');
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 18,
                      color: Color(0xFF667085),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$youth · ${_int(row['quantity'])} Stk.',
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zurückgeben',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _returnAssignment(row),
                      icon: const Icon(
                        Icons.keyboard_return,
                        color: _green,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (active.length > 3)
              Text(
                '+ ${active.length - 3} weitere Ausgabe(n)',
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 12,
                ),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showHistory(item),
                icon: const Icon(Icons.history),
                label: const Text('Verlauf'),
              ),
              FilledButton.icon(
                onPressed: available > 0 ? () => _assignItem(item) : null,
                icon: const Icon(Icons.outbox_outlined),
                label: const Text('Ausgeben'),
              ),
              IconButton(
                tooltip: 'Bearbeiten',
                onPressed: () => _editItem(item: item),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Löschen',
                onPressed: () => _deleteItem(item),
                icon: const Icon(
                  Icons.delete_outline,
                  color: _red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MaterialEditor extends StatefulWidget {
  final Map<String, dynamic>? item;

  const _MaterialEditor({this.item});

  @override
  State<_MaterialEditor> createState() => _MaterialEditorState();
}

class _MaterialEditorState extends State<_MaterialEditor> {
  static const _red = Color(0xFFE30613);

  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _inventoryNumber;
  late final TextEditingController _size;
  late final TextEditingController _total;
  late final TextEditingController _defective;
  late final TextEditingController _minimum;
  late final TextEditingController _location;
  late final TextEditingController _notes;

  String _category = 'sonstiges';
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final item = widget.item ?? const <String, dynamic>{};

    _name = TextEditingController(text: item['name']?.toString() ?? '');
    _inventoryNumber = TextEditingController(
      text: item['inventory_number']?.toString() ?? '',
    );
    _size = TextEditingController(text: item['size']?.toString() ?? '');
    _total = TextEditingController(
      text: ((item['total_quantity'] as num?)?.toInt() ?? 1).toString(),
    );
    _defective = TextEditingController(
      text: ((item['defective_quantity'] as num?)?.toInt() ?? 0).toString(),
    );
    _minimum = TextEditingController(
      text: ((item['minimum_available'] as num?)?.toInt() ?? 0).toString(),
    );
    _location = TextEditingController(
      text: item['storage_location']?.toString() ?? '',
    );
    _notes = TextEditingController(text: item['notes']?.toString() ?? '');

    final category = item['category']?.toString();
    if (category != null && category.isNotEmpty) {
      _category = category;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _inventoryNumber.dispose();
    _size.dispose();
    _total.dispose();
    _defective.dispose();
    _minimum.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final total = int.tryParse(_total.text.trim()) ?? 0;
    final defective = int.tryParse(_defective.text.trim()) ?? 0;
    final minimum = int.tryParse(_minimum.text.trim()) ?? 0;

    if (defective > total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Der Defektbestand darf nicht größer als der Gesamtbestand sein.'),
        ),
      );
      return;
    }

    String? clean(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'category': _category,
      'inventory_number': clean(_inventoryNumber),
      'size': clean(_size),
      'total_quantity': total,
      'defective_quantity': defective,
      'minimum_available': minimum,
      'storage_location': clean(_location),
      'notes': clean(_notes),
    };

    setState(() => _saving = true);

    try {
      if (widget.item == null) {
        await _supabase.from('material_items').insert({
          ...data,
          'created_by': user.id,
        });
      } else {
        await _supabase
            .from('material_items')
            .update(data)
            .eq('id', widget.item!['id']);
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
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item == null ? 'Material anlegen' : 'Material bearbeiten',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Bezeichnung *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Bitte eine Bezeichnung eingeben.'
                        : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Kategorie',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'schutzkleidung',
                    child: Text('Schutzkleidung'),
                  ),
                  DropdownMenuItem(value: 'helm', child: Text('Helm')),
                  DropdownMenuItem(
                    value: 'handschuhe',
                    child: Text('Handschuhe'),
                  ),
                  DropdownMenuItem(value: 'funk', child: Text('Funk')),
                  DropdownMenuItem(value: 'geraet', child: Text('Gerät')),
                  DropdownMenuItem(
                    value: 'sonstiges',
                    child: Text('Sonstiges'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _inventoryNumber,
                decoration: const InputDecoration(
                  labelText: 'Inventar-Nr.',
                  prefixIcon: Icon(Icons.qr_code_2_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _size,
                decoration: const InputDecoration(
                  labelText: 'Größe',
                  prefixIcon: Icon(Icons.straighten_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _total,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Gesamt *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final number = int.tryParse(value?.trim() ?? '');
                        if (number == null || number <= 0) {
                          return 'Mind. 1';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _defective,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Defekt',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final number = int.tryParse(value?.trim() ?? '');
                        if (number == null || number < 0) return 'Ungültig';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _minimum,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Minimum',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final number = int.tryParse(value?.trim() ?? '');
                        if (number == null || number < 0) return 'Ungültig';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'Lagerort',
                  prefixIcon: Icon(Icons.place_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Bemerkungen',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: _red),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Speichern...' : 'Speichern'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialAssignmentEditor extends StatefulWidget {
  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> youth;
  final int available;

  const _MaterialAssignmentEditor({
    required this.item,
    required this.youth,
    required this.available,
  });

  @override
  State<_MaterialAssignmentEditor> createState() =>
      _MaterialAssignmentEditorState();
}

class _MaterialAssignmentEditorState
    extends State<_MaterialAssignmentEditor> {
  static const _red = Color(0xFFE30613);

  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  String? _youthId;
  late final TextEditingController _quantity;
  late final TextEditingController _note;

  DateTime _issuedAt = DateTime.now();
  DateTime? _dueBackAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController(text: '1');
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  String _name(Map<String, dynamic> youth) {
    final first = youth['first_name']?.toString().trim() ?? '';
    final last = youth['last_name']?.toString().trim() ?? '';
    final value = '$first $last'.trim();
    return value.isEmpty ? 'Jugendmitglied' : value;
  }

  String _date(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  String _dbDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickIssued() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _issuedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 5),
    );

    if (result != null) setState(() => _issuedAt = result);
  }

  Future<void> _pickDue() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _dueBackAt ?? _issuedAt,
      firstDate: _issuedAt,
      lastDate: DateTime(DateTime.now().year + 10),
    );

    if (result != null) setState(() => _dueBackAt = result);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    if (_youthId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte ein Jugendmitglied auswählen.')),
      );
      return;
    }

    final quantity = int.tryParse(_quantity.text.trim()) ?? 0;

    if (quantity > widget.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Es sind nur ${widget.available} Stück verfügbar.',
          ),
        ),
      );
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final note = _note.text.trim();

    setState(() => _saving = true);

    try {
      await _supabase.from('material_assignments').insert({
        'material_id': widget.item['id'],
        'youth_id': _youthId,
        'quantity': quantity,
        'issued_at': _dbDate(_issuedAt),
        'due_back_at': _dueBackAt == null ? null : _dbDate(_dueBackAt!),
        'note': note.isEmpty ? null : note,
        'created_by': user.id,
        'updated_by': user.id,
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ausgabe fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.item['name']} ausgeben',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.available} Stück verfügbar',
                style: const TextStyle(color: Color(0xFF667085)),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _youthId,
                decoration: const InputDecoration(
                  labelText: 'Jugendmitglied *',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                items: widget.youth
                    .map(
                      (youth) => DropdownMenuItem<String>(
                        value: youth['id'].toString(),
                        child: Text(_name(youth)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _youthId = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Menge *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final number = int.tryParse(value?.trim() ?? '');
                  if (number == null || number <= 0) {
                    return 'Bitte eine gültige Menge eingeben.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.outbox_outlined),
                title: const Text('Ausgabedatum'),
                subtitle: Text(_date(_issuedAt)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickIssued,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.keyboard_return),
                title: const Text('Geplante Rückgabe'),
                subtitle: Text(
                  _dueBackAt == null ? 'Keine Frist' : _date(_dueBackAt!),
                ),
                trailing: Wrap(
                  spacing: 2,
                  children: [
                    if (_dueBackAt != null)
                      IconButton(
                        tooltip: 'Frist entfernen',
                        onPressed: () => setState(() => _dueBackAt = null),
                        icon: const Icon(Icons.close),
                      ),
                    IconButton(
                      tooltip: 'Datum auswählen',
                      onPressed: _pickDue,
                      icon: const Icon(Icons.edit_calendar_outlined),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Bemerkung',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: _red),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.outbox_outlined),
                  label: Text(_saving ? 'Speichern...' : 'Material ausgeben'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _SummaryBox({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _InfoPill({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Color(0xFF4B5563),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LineInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const _LineInfo({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: const Color(0xFF667085),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF4B5563),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyBox({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3E8EE)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 64,
            color: const Color(0xFF0B4EA2),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF0A1F44),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
