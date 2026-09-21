import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemberRecordsScreen extends StatefulWidget {
  const MemberRecordsScreen({super.key});

  @override
  State<MemberRecordsScreen> createState() => _MemberRecordsScreenState();
}

class _MemberRecordsScreenState extends State<MemberRecordsScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _red = Color(0xFFE30613);
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  String? _error;
  List<Map<String, dynamic>> _youth = [];
  Map<String, Map<String, dynamic>> _records = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Kein Benutzer angemeldet.');

      final own = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final isTrainer = own?['role']?.toString() == 'ausbilder';
      if (!isTrainer) {
        if (!mounted) return;
        setState(() {
          _isTrainer = false;
          _loading = false;
        });
        return;
      }

      final youthRows = await _supabase
          .from('profiles')
          .select('id,first_name,last_name,phone,role')
          .eq('role', 'jugendmitglied')
          .order('last_name')
          .order('first_name');

      final recordRows = await _supabase.from('youth_member_records').select();

      final byYouth = <String, Map<String, dynamic>>{};
      for (final raw in recordRows) {
        final row = Map<String, dynamic>.from(raw);
        final youthId = row['youth_id']?.toString();
        if (youthId != null && youthId.isNotEmpty) {
          byYouth[youthId] = row;
        }
      }

      if (!mounted) return;
      setState(() {
        _isTrainer = true;
        _youth = List<Map<String, dynamic>>.from(youthRows);
        _records = byYouth;
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

  String _name(Map<String, dynamic> p) {
    final first = p['first_name']?.toString().trim() ?? '';
    final last = p['last_name']?.toString().trim() ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Jugendmitglied' : name;
  }

  Future<void> _open(Map<String, dynamic> youth) async {
    final id = youth['id']?.toString() ?? '';
    if (id.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MemberRecordEditor(
          youth: youth,
          initialRecord: _records[id],
        ),
      ),
    );

    if (mounted) {
      setState(() => _loading = true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: const Text('Stammblätter'),
        backgroundColor: Colors.white,
        foregroundColor: _navy,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_isTrainer
              ? const Center(
                  child: Text(
                    'Dieser Bereich ist ausschließlich für Ausbilder freigegeben.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFE3E8EE),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.badge_outlined, color: _red),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Interne Stammblätter – nur für Ausbilder sichtbar.',
                                style: TextStyle(
                                  color: _navy,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        '${_youth.length} Jugendmitglieder',
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._youth.map((youth) {
                        final id = youth['id']?.toString() ?? '';
                        final exists = _records.containsKey(id);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const Icon(
                              Icons.person_outline,
                              color: _red,
                            ),
                            title: Text(
                              _name(youth),
                              style: const TextStyle(
                                color: _navy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              exists
                                  ? 'Stammblatt vorhanden'
                                  : 'Noch kein Stammblatt angelegt',
                            ),
                            trailing: Icon(
                              exists
                                  ? Icons.chevron_right
                                  : Icons.add_circle_outline,
                            ),
                            onTap: () => _open(youth),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}

class _MemberRecordEditor extends StatefulWidget {
  final Map<String, dynamic> youth;
  final Map<String, dynamic>? initialRecord;

  const _MemberRecordEditor({
    required this.youth,
    required this.initialRecord,
  });

  @override
  State<_MemberRecordEditor> createState() => _MemberRecordEditorState();
}

class _MemberRecordEditorState extends State<_MemberRecordEditor> {
  static const _navy = Color(0xFF0A1F44);
  static const _red = Color(0xFFE30613);

  final _supabase = Supabase.instance.client;

  late final TextEditingController street;
  late final TextEditingController postalCode;
  late final TextEditingController city;
  late final TextEditingController email;
  late final TextEditingController membershipNumber;
  late final TextEditingController guardianName;
  late final TextEditingController guardianPhone;
  late final TextEditingController guardianEmail;
  late final TextEditingController emergencyName;
  late final TextEditingController emergencyPhone;
  late final TextEditingController clothingSize;
  late final TextEditingController helmetSize;
  late final TextEditingController notes;

  DateTime? birthDate;
  DateTime? entryDate;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.initialRecord ?? const <String, dynamic>{};

    TextEditingController c(String key) =>
        TextEditingController(text: r[key]?.toString() ?? '');

    street = c('street');
    postalCode = c('postal_code');
    city = c('city');
    email = c('email');
    membershipNumber = c('membership_number');
    guardianName = c('guardian_name');
    guardianPhone = c('guardian_phone');
    guardianEmail = c('guardian_email');
    emergencyName = c('emergency_contact_name');
    emergencyPhone = c('emergency_contact_phone');
    clothingSize = c('clothing_size');
    helmetSize = c('helmet_size');
    notes = c('notes');
    birthDate = DateTime.tryParse(r['birth_date']?.toString() ?? '');
    entryDate = DateTime.tryParse(r['entry_date']?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      street,
      postalCode,
      city,
      email,
      membershipNumber,
      guardianName,
      guardianPhone,
      guardianEmail,
      emergencyName,
      emergencyPhone,
      clothingSize,
      helmetSize,
      notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get memberName {
    final first = widget.youth['first_name']?.toString().trim() ?? '';
    final last = widget.youth['last_name']?.toString().trim() ?? '';
    final value = '$first $last'.trim();
    return value.isEmpty ? 'Jugendmitglied' : value;
  }

  String dateLabel(DateTime? d) {
    if (d == null) return 'Nicht angegeben';
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String? dbDate(DateTime? d) {
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<DateTime?> pick(DateTime? current, {bool pastOnly = false}) {
    return showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: pastOnly ? DateTime.now() : DateTime(DateTime.now().year + 5),
    );
  }

  Widget field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget section(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
            color: _navy,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

  Future<void> save() async {
    if (saving) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => saving = true);

    String? clean(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    final data = <String, dynamic>{
      'youth_id': widget.youth['id'],
      'birth_date': dbDate(birthDate),
      'street': clean(street),
      'postal_code': clean(postalCode),
      'city': clean(city),
      'email': clean(email),
      'entry_date': dbDate(entryDate),
      'membership_number': clean(membershipNumber),
      'guardian_name': clean(guardianName),
      'guardian_phone': clean(guardianPhone),
      'guardian_email': clean(guardianEmail),
      'emergency_contact_name': clean(emergencyName),
      'emergency_contact_phone': clean(emergencyPhone),
      'clothing_size': clean(clothingSize),
      'helmet_size': clean(helmetSize),
      'notes': clean(notes),
      'updated_by': user.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      if (widget.initialRecord == null) {
        data['created_by'] = user.id;
        await _supabase.from('youth_member_records').insert(data);
      } else {
        await _supabase
            .from('youth_member_records')
            .update(data)
            .eq('youth_id', widget.youth['id']);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stammblatt gespeichert.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: Text(memberName),
        backgroundColor: Colors.white,
        foregroundColor: _navy,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          section('Persönliche Daten'),
          ListTile(
            tileColor: Colors.white,
            title: const Text('Geburtsdatum'),
            subtitle: Text(dateLabel(birthDate)),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: () async {
              final d = await pick(birthDate, pastOnly: true);
              if (d != null) setState(() => birthDate = d);
            },
          ),
          const SizedBox(height: 12),
          field(email, 'E-Mail Jugendmitglied',
              keyboardType: TextInputType.emailAddress),
          field(street, 'Straße und Hausnummer'),
          field(postalCode, 'PLZ', keyboardType: TextInputType.number),
          field(city, 'Ort'),
          section('Jugendfeuerwehr'),
          ListTile(
            tileColor: Colors.white,
            title: const Text('Eintrittsdatum'),
            subtitle: Text(dateLabel(entryDate)),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: () async {
              final d = await pick(entryDate);
              if (d != null) setState(() => entryDate = d);
            },
          ),
          const SizedBox(height: 12),
          field(membershipNumber, 'Mitglieds-/Dienstnummer'),
          field(clothingSize, 'Kleidergröße'),
          field(helmetSize, 'Helmgröße'),
          section('Erziehungsberechtigte'),
          field(guardianName, 'Name'),
          field(guardianPhone, 'Telefon', keyboardType: TextInputType.phone),
          field(guardianEmail, 'E-Mail',
              keyboardType: TextInputType.emailAddress),
          section('Notfallkontakt'),
          field(emergencyName, 'Name'),
          field(emergencyPhone, 'Telefon', keyboardType: TextInputType.phone),
          section('Interne Bemerkungen'),
          field(notes, 'Bemerkungen', maxLines: 5),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: saving ? null : save,
            style: FilledButton.styleFrom(
              backgroundColor: _red,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(saving ? 'Speichern...' : 'Stammblatt speichern'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
