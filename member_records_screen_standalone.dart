import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/home_navigation.dart';

class MemberRecordsScreen extends StatefulWidget {
  const MemberRecordsScreen({super.key});

  @override
  State<MemberRecordsScreen> createState() => _MemberRecordsScreenState();
}

class _MemberRecordsScreenState extends State<MemberRecordsScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  String? _error;
  String _query = '';

  List<Map<String, dynamic>> _youth = [];
  Map<String, Map<String, dynamic>> _recordsByYouth = {};
  List<Map<String, dynamic>> _standaloneRecords = [];

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

      final result = await Future.wait([
        _supabase
            .from('profiles')
            .select('id,first_name,last_name,phone,role')
            .eq('role', 'jugendmitglied')
            .order('last_name')
            .order('first_name'),
        _supabase
            .from('youth_member_records')
            .select()
            .order('last_name')
            .order('first_name'),
      ]);

      final youthRows = List<Map<String, dynamic>>.from(result[0]);
      final recordRows = List<Map<String, dynamic>>.from(result[1]);

      final byYouth = <String, Map<String, dynamic>>{};
      final standalone = <Map<String, dynamic>>[];

      for (final row in recordRows) {
        final youthId = row['youth_id']?.toString();

        if (youthId == null || youthId.isEmpty) {
          standalone.add(row);
        } else {
          byYouth[youthId] = row;
        }
      }

      if (!mounted) return;

      setState(() {
        _isTrainer = true;
        _youth = youthRows;
        _recordsByYouth = byYouth;
        _standaloneRecords = standalone;
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

  String _profileName(Map<String, dynamic> profile) {
    final first = profile['first_name']?.toString().trim() ?? '';
    final last = profile['last_name']?.toString().trim() ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Jugendmitglied' : name;
  }

  String _recordName(Map<String, dynamic> record) {
    final first = record['first_name']?.toString().trim() ?? '';
    final last = record['last_name']?.toString().trim() ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Jugendmitglied ohne App-Konto' : name;
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  List<Map<String, dynamic>> get _filteredYouth {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _youth;
    return _youth
        .where((youth) => _profileName(youth).toLowerCase().contains(q))
        .toList();
  }

  List<Map<String, dynamic>> get _filteredStandalone {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _standaloneRecords;

    return _standaloneRecords.where((record) {
      final haystack = [
        _recordName(record),
        record['city'],
        record['membership_number'],
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');

      return haystack.contains(q);
    }).toList();
  }

  Future<void> _openLinked(Map<String, dynamic> youth) async {
    final id = youth['id']?.toString() ?? '';
    if (id.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MemberRecordEditor(
          youth: youth,
          initialRecord: _recordsByYouth[id],
        ),
      ),
    );

    if (mounted) await _load();
  }

  Future<void> _openStandalone({Map<String, dynamic>? record}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MemberRecordEditor(
          youth: null,
          initialRecord: record,
        ),
      ),
    );

    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        title: const Text('Stammblätter'),
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        actions: [
          IconButton(
            tooltip: 'Zur Startseite',
            onPressed: () => HomeNavigation.goHome(context),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      floatingActionButton: _isTrainer
          ? FloatingActionButton.extended(
              onPressed: () => _openStandalone(),
              backgroundColor: _red,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Ohne App-Konto'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_isTrainer
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Dieser Bereich ist ausschließlich für Ausbilder freigegeben.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.badge_outlined,
                              color: Colors.white,
                              size: 32,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Stammblätter für App-Mitglieder und '
                                'Jugendmitglieder ohne eigenes App-Konto',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  height: 1.3,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => _openStandalone(),
                        style: FilledButton.styleFrom(
                          backgroundColor: _red,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text(
                          'Stammblatt ohne App-Konto anlegen',
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: _red),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: 'Stammblatt suchen',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _SectionHeading(
                        title: 'Mit App-Konto',
                        count: _filteredYouth.length,
                        icon: Icons.smartphone_outlined,
                      ),
                      const SizedBox(height: 10),
                      if (_filteredYouth.isEmpty)
                        const _EmptyCard(
                          text: 'Keine passenden App-Mitglieder gefunden.',
                        )
                      else
                        ..._filteredYouth.map((youth) {
                          final id = youth['id']?.toString() ?? '';
                          final exists = _recordsByYouth.containsKey(id);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: exists
                                    ? const Color(0xFFE8F6EE)
                                    : const Color(0xFFFFE6E8),
                                child: Icon(
                                  exists
                                      ? Icons.badge_outlined
                                      : Icons.person_outline,
                                  color: exists ? _green : _red,
                                ),
                              ),
                              title: Text(
                                _profileName(youth),
                                style: const TextStyle(
                                  color: _navy,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                exists
                                    ? 'Stammblatt vorhanden · mit App-Konto'
                                    : 'Noch kein Stammblatt angelegt',
                              ),
                              trailing: Icon(
                                exists
                                    ? Icons.chevron_right
                                    : Icons.add_circle_outline,
                              ),
                              onTap: () => _openLinked(youth),
                            ),
                          );
                        }),
                      const SizedBox(height: 22),
                      _SectionHeading(
                        title: 'Ohne App-Konto',
                        count: _filteredStandalone.length,
                        icon: Icons.person_off_outlined,
                      ),
                      const SizedBox(height: 10),
                      if (_filteredStandalone.isEmpty)
                        const _EmptyCard(
                          text:
                              'Noch keine Stammblätter ohne App-Konto angelegt.',
                        )
                      else
                        ..._filteredStandalone.map((record) {
                          final birthDate = _date(record['birth_date']);
                          final city =
                              record['city']?.toString().trim() ?? '';

                          final details = <String>[
                            'Kein App-Konto',
                            if (birthDate.isNotEmpty) 'geb. $birthDate',
                            if (city.isNotEmpty) city,
                          ].join(' · ');

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFEAF2FB),
                                child: Icon(
                                  Icons.person_off_outlined,
                                  color: _blue,
                                ),
                              ),
                              title: Text(
                                _recordName(record),
                                style: const TextStyle(
                                  color: _navy,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(details),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openStandalone(record: record),
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
  final Map<String, dynamic>? youth;
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
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);

  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController firstName;
  late final TextEditingController lastName;
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
  late final TextEditingController emergencyName2;
  late final TextEditingController emergencyPhone2;
  late final TextEditingController emergencyName3;
  late final TextEditingController emergencyPhone3;
  late final TextEditingController emergencyName4;
  late final TextEditingController emergencyPhone4;
  late final TextEditingController clothingSize;
  late final TextEditingController helmetSize;
  late final TextEditingController notes;
  late final TextEditingController healthInsurance;
  late final TextEditingController allergies;
  late final TextEditingController pickupPhone;
  late final TextEditingController homeWayNotes;
  late final TextEditingController groupMovementNotes;
  late final TextEditingController swimmingStage;
  late final TextEditingController swimmingNotes;
  late final TextEditingController mediaNotes;

  DateTime? birthDate;
  DateTime? entryDate;
  DateTime? recordAsOf;

  String? homeWay;
  bool? groupMovementAllowed;
  bool? swimmingAllowed;
  String? swimmingLevel;
  bool? mediaRecordingAllowed;
  bool? mediaPublicationAllowed;

  bool saving = false;

  bool get isStandalone => widget.youth == null;

  @override
  void initState() {
    super.initState();

    final record = widget.initialRecord ?? const <String, dynamic>{};

    String initialName(String key) {
      final fromRecord = record[key]?.toString().trim() ?? '';
      if (fromRecord.isNotEmpty) return fromRecord;
      return widget.youth?[key]?.toString().trim() ?? '';
    }

    TextEditingController c(String key) =>
        TextEditingController(text: record[key]?.toString() ?? '');

    firstName = TextEditingController(text: initialName('first_name'));
    lastName = TextEditingController(text: initialName('last_name'));
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
    emergencyName2 = c('emergency_contact_2_name');
    emergencyPhone2 = c('emergency_contact_2_phone');
    emergencyName3 = c('emergency_contact_3_name');
    emergencyPhone3 = c('emergency_contact_3_phone');
    emergencyName4 = c('emergency_contact_4_name');
    emergencyPhone4 = c('emergency_contact_4_phone');
    clothingSize = c('clothing_size');
    helmetSize = c('helmet_size');
    notes = c('notes');
    healthInsurance = c('health_insurance');
    allergies = c('allergies');
    pickupPhone = c('pickup_phone');
    homeWayNotes = c('home_way_notes');
    groupMovementNotes = c('group_movement_notes');
    swimmingStage = c('swimming_stage');
    swimmingNotes = c('swimming_notes');
    mediaNotes = c('media_notes');

    birthDate = DateTime.tryParse(record['birth_date']?.toString() ?? '');
    entryDate = DateTime.tryParse(record['entry_date']?.toString() ?? '');
    recordAsOf = DateTime.tryParse(record['record_as_of']?.toString() ?? '');

    homeWay = _nullableString(record['home_way']);
    groupMovementAllowed =
        _nullableBool(record['group_movement_allowed']);
    swimmingAllowed = _nullableBool(record['swimming_allowed']);
    swimmingLevel = _nullableString(record['swimming_level']);
    mediaRecordingAllowed =
        _nullableBool(record['media_recording_allowed']);
    mediaPublicationAllowed =
        _nullableBool(record['media_publication_allowed']);
  }

  String? _nullableString(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  bool? _nullableBool(dynamic value) {
    if (value is bool) return value;
    if (value?.toString() == 'true') return true;
    if (value?.toString() == 'false') return false;
    return null;
  }

  @override
  void dispose() {
    for (final controller in [
      firstName,
      lastName,
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
      emergencyName2,
      emergencyPhone2,
      emergencyName3,
      emergencyPhone3,
      emergencyName4,
      emergencyPhone4,
      clothingSize,
      helmetSize,
      notes,
      healthInsurance,
      allergies,
      pickupPhone,
      homeWayNotes,
      groupMovementNotes,
      swimmingStage,
      swimmingNotes,
      mediaNotes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String get memberName {
    final value = '${firstName.text.trim()} ${lastName.text.trim()}'.trim();
    return value.isEmpty ? 'Neues Stammblatt' : value;
  }

  String dateLabel(DateTime? date) {
    if (date == null) return 'Nicht angegeben';
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  String? dbDate(DateTime? date) {
    if (date == null) return null;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<DateTime?> pick(
    DateTime? current, {
    bool pastOnly = false,
  }) {
    final today = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current ?? today,
      firstDate: DateTime(1990),
      lastDate: pastOnly ? today : DateTime(today.year + 5),
    );
  }

  Widget field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    int maxLines = 1,
    String? hintText,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hintText,
          border: const OutlineInputBorder(),
        ),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                ? 'Bitte $label eingeben.'
                : null
            : null,
      ),
    );
  }

  Widget section(String text, {IconData? icon, String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: _red, size: 24),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget infoValue(String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E0E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? 'Nicht angegeben' : value,
            style: const TextStyle(
              color: _navy,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget dateTile(
    String title,
    DateTime? value,
    Future<void> Function() onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E0E7)),
      ),
      child: ListTile(
        title: Text(title),
        subtitle: Text(dateLabel(value)),
        trailing: const Icon(Icons.calendar_month_outlined),
        onTap: onTap,
      ),
    );
  }

  Widget stringChoice({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value ?? '',
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem<String>(
            value: '',
            child: Text('Nicht angegeben'),
          ),
          ...items,
        ],
        onChanged: (selected) {
          onChanged(
            selected == null || selected.isEmpty ? null : selected,
          );
        },
      ),
    );
  }

  Widget boolChoice({
    required String label,
    required bool? value,
    required String yesLabel,
    required String noLabel,
    required ValueChanged<bool?> onChanged,
  }) {
    final current = value == true
        ? 'yes'
        : value == false
            ? 'no'
            : 'unset';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: current,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(
            value: 'unset',
            child: Text('Nicht angegeben'),
          ),
          DropdownMenuItem(
            value: 'yes',
            child: Text(yesLabel),
          ),
          DropdownMenuItem(
            value: 'no',
            child: Text(noLabel),
          ),
        ],
        onChanged: (selected) {
          if (selected == 'yes') {
            onChanged(true);
          } else if (selected == 'no') {
            onChanged(false);
          } else {
            onChanged(null);
          }
        },
      ),
    );
  }

  Widget contactCard({
    required int number,
    required TextEditingController name,
    required TextEditingController phone,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E8EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kontakt $number',
            style: const TextStyle(
              color: _navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Telefonnummer',
              prefixIcon: Icon(Icons.phone_outlined),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> save() async {
    if (saving) return;

    if (isStandalone && !_formKey.currentState!.validate()) {
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    String? clean(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    final linkedFirst =
        widget.youth?['first_name']?.toString().trim() ?? '';
    final linkedLast =
        widget.youth?['last_name']?.toString().trim() ?? '';

    final finalFirst =
        isStandalone ? firstName.text.trim() : linkedFirst;
    final finalLast =
        isStandalone ? lastName.text.trim() : linkedLast;

    if (finalFirst.isEmpty || finalLast.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vorname und Nachname müssen angegeben werden.'),
        ),
      );
      return;
    }

    setState(() => saving = true);

    final data = <String, dynamic>{
      'youth_id': widget.youth?['id'],
      'first_name': finalFirst,
      'last_name': finalLast,
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
      'emergency_contact_2_name': clean(emergencyName2),
      'emergency_contact_2_phone': clean(emergencyPhone2),
      'emergency_contact_3_name': clean(emergencyName3),
      'emergency_contact_3_phone': clean(emergencyPhone3),
      'emergency_contact_4_name': clean(emergencyName4),
      'emergency_contact_4_phone': clean(emergencyPhone4),
      'clothing_size': clean(clothingSize),
      'helmet_size': clean(helmetSize),
      'notes': clean(notes),
      'health_insurance': clean(healthInsurance),
      'allergies': clean(allergies),
      'home_way': homeWay,
      'pickup_phone': clean(pickupPhone),
      'home_way_notes': clean(homeWayNotes),
      'group_movement_allowed': groupMovementAllowed,
      'group_movement_notes': clean(groupMovementNotes),
      'swimming_allowed': swimmingAllowed,
      'swimming_level': swimmingLevel,
      'swimming_stage': clean(swimmingStage),
      'swimming_notes': clean(swimmingNotes),
      'media_recording_allowed': mediaRecordingAllowed,
      'media_publication_allowed': mediaPublicationAllowed,
      'media_notes': clean(mediaNotes),
      'record_as_of': dbDate(recordAsOf),
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
            .eq('id', widget.initialRecord!['id']);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isStandalone
                ? 'Stammblatt ohne App-Konto gespeichert.'
                : 'Stammblatt gespeichert.',
          ),
        ),
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
        actions: [
          IconButton(
            tooltip: 'Zur Startseite',
            onPressed: () => HomeNavigation.goHome(context),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_navy, _blue]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.badge_outlined,
                    color: Colors.white,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isStandalone
                          ? 'Stammdatenblatt ohne App-Konto'
                          : 'Stammdatenblatt Jugendfeuerwehr Seehausen',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isStandalone) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: _blue),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Für dieses Stammblatt wird kein Benutzerkonto '
                        'in der App benötigt.',
                        style: TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            section('Persönliche Angaben', icon: Icons.person_outline),

            if (isStandalone) ...[
              field(firstName, 'Vorname', required: true),
              field(lastName, 'Nachname', required: true),
            ] else ...[
              infoValue(
                'Vorname',
                widget.youth?['first_name']?.toString().trim() ?? '',
              ),
              infoValue(
                'Name',
                widget.youth?['last_name']?.toString().trim() ?? '',
              ),
            ],

            dateTile(
              'Geburtsdatum',
              birthDate,
              () async {
                final date = await pick(birthDate, pastOnly: true);
                if (date != null) setState(() => birthDate = date);
              },
            ),
            field(healthInsurance, 'Krankenkasse'),
            field(street, 'Straße und Hausnummer'),
            field(
              postalCode,
              'PLZ',
              keyboardType: TextInputType.number,
            ),
            field(city, 'Ort'),
            field(
              allergies,
              'Allergien',
              maxLines: 3,
              hintText: 'z. B. keine / Pollen / Medikamente',
            ),

            section(
              'Notrufnummern',
              icon: Icons.contact_phone_outlined,
              subtitle: 'Bis zu vier Notfallkontakte',
            ),
            contactCard(
              number: 1,
              name: emergencyName,
              phone: emergencyPhone,
            ),
            contactCard(
              number: 2,
              name: emergencyName2,
              phone: emergencyPhone2,
            ),
            contactCard(
              number: 3,
              name: emergencyName3,
              phone: emergencyPhone3,
            ),
            contactCard(
              number: 4,
              name: emergencyName4,
              phone: emergencyPhone4,
            ),

            section('Heimweg', icon: Icons.home_outlined),
            stringChoice(
              label: 'Regelung für den Heimweg',
              value: homeWay,
              items: const [
                DropdownMenuItem(
                  value: 'selbststaendig',
                  child: Text('Darf selbstständig nach Hause gehen'),
                ),
                DropdownMenuItem(
                  value: 'abholung',
                  child: Text('Wird abgeholt'),
                ),
              ],
              onChanged: (value) => setState(() => homeWay = value),
            ),
            if (homeWay == 'abholung')
              field(
                pickupPhone,
                'Bei Abholung bitte anrufen unter',
                keyboardType: TextInputType.phone,
              ),
            field(
              homeWayNotes,
              'Bemerkung Heimweg',
              maxLines: 3,
            ),

            section(
              'Selbstständiges Bewegen in einer Gruppe',
              icon: Icons.groups_outlined,
              subtitle: 'Mindestens 3 Kinder / Jugendliche',
            ),
            boolChoice(
              label: 'Darf sich selbstständig in der Gruppe bewegen?',
              value: groupMovementAllowed,
              yesLabel: 'Ja',
              noLabel: 'Nein',
              onChanged: (value) =>
                  setState(() => groupMovementAllowed = value),
            ),
            field(
              groupMovementNotes,
              'Bemerkung Gruppenbewegung',
              maxLines: 3,
            ),

            section(
              'Schwimm- und Badeerlaubnis',
              icon: Icons.pool_outlined,
            ),
            boolChoice(
              label: 'Teilnahme am Schwimmen / Baden',
              value: swimmingAllowed,
              yesLabel: 'Darf teilnehmen',
              noLabel: 'Darf nicht teilnehmen',
              onChanged: (value) =>
                  setState(() => swimmingAllowed = value),
            ),
            stringChoice(
              label: 'Schwimmstatus',
              value: swimmingLevel,
              items: const [
                DropdownMenuItem(
                  value: 'nichtschwimmer',
                  child: Text('Nichtschwimmer'),
                ),
                DropdownMenuItem(
                  value: 'seepferdchen',
                  child: Text('Seepferdchen'),
                ),
                DropdownMenuItem(
                  value: 'schwimmstufe',
                  child: Text('Schwimmstufe'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => swimmingLevel = value),
            ),
            if (swimmingLevel == 'schwimmstufe')
              field(
                swimmingStage,
                'Schwimmstufe',
                hintText: 'z. B. Bronze, Silber, Gold',
              ),
            field(
              swimmingNotes,
              'Bemerkung Schwimmen / Baden',
              maxLines: 3,
            ),

            section(
              'Foto-, Video- und Medienaufzeichnungen',
              icon: Icons.photo_camera_outlined,
            ),
            boolChoice(
              label: 'Foto- und Videoaufnahmen',
              value: mediaRecordingAllowed,
              yesLabel: 'Darf fotografiert / gefilmt werden',
              noLabel: 'Darf nicht fotografiert / gefilmt werden',
              onChanged: (value) =>
                  setState(() => mediaRecordingAllowed = value),
            ),
            boolChoice(
              label: 'Veröffentlichung',
              value: mediaPublicationAllowed,
              yesLabel: 'Darf veröffentlicht werden',
              noLabel: 'Darf nicht veröffentlicht werden',
              onChanged: (value) =>
                  setState(() => mediaPublicationAllowed = value),
            ),
            field(
              mediaNotes,
              'Bemerkung Foto / Video / Medien',
              maxLines: 3,
            ),

            section(
              'Stand des Stammblatts',
              icon: Icons.update_outlined,
            ),
            dateTile(
              'Stand',
              recordAsOf,
              () async {
                final date = await pick(recordAsOf, pastOnly: true);
                if (date != null) setState(() => recordAsOf = date);
              },
            ),

            section(
              'Weitere interne Angaben',
              icon: Icons.shield_outlined,
              subtitle: 'Interne Daten der Jugendfeuerwehr',
            ),
            field(
              email,
              'E-Mail Jugendmitglied',
              keyboardType: TextInputType.emailAddress,
            ),
            dateTile(
              'Eintrittsdatum Jugendfeuerwehr',
              entryDate,
              () async {
                final date = await pick(entryDate);
                if (date != null) setState(() => entryDate = date);
              },
            ),
            field(membershipNumber, 'Mitglieds-/Dienstnummer'),
            field(clothingSize, 'Kleidergröße'),
            field(helmetSize, 'Helmgröße'),

            section(
              'Erziehungsberechtigte',
              icon: Icons.family_restroom,
            ),
            field(guardianName, 'Name'),
            field(
              guardianPhone,
              'Telefon',
              keyboardType: TextInputType.phone,
            ),
            field(
              guardianEmail,
              'E-Mail',
              keyboardType: TextInputType.emailAddress,
            ),

            section(
              'Interne Bemerkungen',
              icon: Icons.notes_outlined,
            ),
            field(notes, 'Bemerkungen', maxLines: 5),

            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: saving ? null : save,
              style: FilledButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
              ),
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                saving
                    ? 'Speichern...'
                    : isStandalone
                        ? 'Stammblatt ohne App-Konto speichern'
                        : 'Stammblatt speichern',
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;

  const _SectionHeading({
    required this.title,
    required this.count,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0B4EA2)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0A1F44),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 9,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FB),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFF0B4EA2),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;

  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E8EE)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF667085),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
