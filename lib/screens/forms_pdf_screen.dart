import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/home_navigation.dart';

class FormsPdfScreen extends StatefulWidget {
  const FormsPdfScreen({super.key});

  @override
  State<FormsPdfScreen> createState() => _FormsPdfScreenState();
}

class _FormsPdfScreenState extends State<FormsPdfScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _green = Color(0xFF13A05B);
  static const _orange = Color(0xFFFF7A00);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isTrainer = false;
  bool _working = false;
  String? _error;

  List<Map<String, dynamic>> _youth = [];
  List<int> _years = [];
  String? _selectedYouthId;
  int? _selectedYear;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Kein Benutzer angemeldet.');
      }

      final own = await _supabase
          .from('profiles')
          .select('role,approval_status')
          .eq('id', user.id)
          .maybeSingle();

      final trainer =
          own?['role']?.toString() == 'ausbilder' &&
          own?['approval_status']?.toString() == 'approved';

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
            .from('profiles')
            .select('id,first_name,last_name,phone,role,approval_status')
            .eq('role', 'jugendmitglied')
            .eq('approval_status', 'approved')
            .order('last_name')
            .order('first_name'),
        _supabase
            .from('training_plans')
            .select('training_date')
            .order('training_date', ascending: false),
      ]);

      final youth = List<Map<String, dynamic>>.from(result[0]);
      final trainingDates = List<Map<String, dynamic>>.from(result[1]);

      final years = <int>{};
      for (final row in trainingDates) {
        final date = DateTime.tryParse(row['training_date']?.toString() ?? '');
        if (date != null) years.add(date.year);
      }

      final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));

      if (!mounted) return;

      setState(() {
        _isTrainer = true;
        _youth = youth;
        _years = sortedYears;
        _selectedYouthId = youth.isEmpty ? null : youth.first['id']?.toString();
        _selectedYear = sortedYears.isEmpty ? null : sortedYears.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _selectedYouth {
    final id = _selectedYouthId;
    if (id == null) return null;

    for (final youth in _youth) {
      if (youth['id']?.toString() == id) return youth;
    }
    return null;
  }

  String _name(Map<String, dynamic>? youth) {
    if (youth == null) return 'Jugendmitglied';

    final first = youth['first_name']?.toString().trim() ?? '';
    final last = youth['last_name']?.toString().trim() ?? '';
    final result = '$first $last'.trim();

    return result.isEmpty ? 'Jugendmitglied' : result;
  }

  String _safeFileName(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[^\wäöüÄÖÜß-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '-';

    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  String _time(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '-';

    final parts = raw.split(':');
    if (parts.length < 2) return raw;

    return '${parts[0].padLeft(2, '0')}:'
        '${parts[1].padLeft(2, '0')}';
  }

  int? _minutes(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    final parts = raw.split(':');
    if (parts.length < 2) return null;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;

    return h * 60 + m;
  }

  String _boolLabel(dynamic value) {
    if (value == true) return 'Ja';
    if (value == false) return 'Nein';
    return 'Nicht angegeben';
  }

  String _homeWayLabel(dynamic value) {
    switch (value?.toString()) {
      case 'selbststaendig':
        return 'Darf selbstständig nach Hause gehen';
      case 'abholung':
        return 'Wird abgeholt';
      default:
        return 'Nicht angegeben';
    }
  }

  String _swimmingLabel(dynamic value) {
    switch (value?.toString()) {
      case 'nichtschwimmer':
        return 'Nichtschwimmer';
      case 'seepferdchen':
        return 'Seepferdchen';
      case 'schwimmstufe':
        return 'Schwimmstufe';
      default:
        return 'Nicht angegeben';
    }
  }

  String _trainingStatus(String status) {
    switch (status) {
      case 'anwesend':
        return 'Anwesend';
      case 'entschuldigt':
        return 'Entschuldigt';
      case 'abwesend':
        return 'Abwesend';
      default:
        return status;
    }
  }

  Future<bool> _confirmPersonalData() async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Personenbezogene Daten'),
            content: const Text(
              'Das PDF kann personenbezogene und teilweise sensible Angaben '
              'enthalten. Bitte nur an berechtigte Personen weitergeben und '
              'nicht ungeschützt veröffentlichen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Fortfahren'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<pw.MemoryImage?> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/branding/logo.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  pw.Widget _pdfHeader(
    pw.Context context,
    pw.MemoryImage? logo,
    String title,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: PdfColor.fromInt(0xffd9e0e7),
            width: 0.8,
          ),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) ...[
            pw.Container(
              width: 42,
              height: 42,
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Jugendfeuerwehr Seehausen/Kyffhäuser',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xff0a1f44),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: const PdfColor.fromInt(0xff667085),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfFooter(pw.Context context) {
    final now = DateTime.now();

    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: PdfColor.fromInt(0xffd9e0e7),
            width: 0.6,
          ),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Erstellt am ${_date(now.toIso8601String())}',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColor.fromInt(0xff667085),
            ),
          ),
          pw.Text(
            'Seite ${context.pageNumber} von ${context.pagesCount}',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColor.fromInt(0xff667085),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfSectionTitle(String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10, bottom: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xffeaf2fb),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: const PdfColor.fromInt(0xff0a1f44),
        ),
      ),
    );
  }

  pw.Widget _pdfKeyValueTable(List<List<String>> rows) {
    return pw.TableHelper.fromTextArray(
      data: rows,
      headerCount: 0,
      cellPadding: const pw.EdgeInsets.all(5),
      border: pw.TableBorder.all(
        color: const PdfColor.fromInt(0xffd9e0e7),
        width: 0.5,
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.35),
        1: pw.FlexColumnWidth(2.65),
      },
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellDecoration: (index, data, rowNum) {
        if (index == 0) {
          return const pw.BoxDecoration(
            color: PdfColor.fromInt(0xfff3f5f7),
          );
        }
        return const pw.BoxDecoration();
      },
    );
  }

  Future<Map<String, dynamic>?> _loadMemberRecord(String youthId) {
    return _supabase
        .from('youth_member_records')
        .select()
        .eq('youth_id', youthId)
        .maybeSingle();
  }

  Future<Uint8List> _buildTrainingCertificate() async {
    final youth = _selectedYouth;
    if (youth == null) throw Exception('Bitte ein Jugendmitglied auswählen.');

    final youthId = youth['id'].toString();

    final result = await Future.wait([
      _supabase
          .from('training_attendance')
          .select('training_plan_id,status,note,marked_at')
          .eq('youth_id', youthId),
      _supabase
          .from('training_plans')
          .select(
            'id,title,topic,training_date,start_time,end_time,location',
          )
          .order('training_date'),
    ]);

    final attendance = List<Map<String, dynamic>>.from(result[0]);
    final plans = List<Map<String, dynamic>>.from(result[1]);

    final plansById = <String, Map<String, dynamic>>{
      for (final plan in plans) plan['id'].toString(): plan,
    };

    final records = <Map<String, dynamic>>[];

    for (final row in attendance) {
      final planId = row['training_plan_id']?.toString();
      if (planId == null) continue;

      final plan = plansById[planId];
      if (plan == null) continue;

      final date = DateTime.tryParse(plan['training_date']?.toString() ?? '');
      if (_selectedYear != null && date?.year != _selectedYear) continue;

      records.add({
        ...row,
        'plan': plan,
      });
    }

    records.sort((a, b) {
      final aPlan = a['plan'] as Map<String, dynamic>;
      final bPlan = b['plan'] as Map<String, dynamic>;
      final aDate =
          DateTime.tryParse(aPlan['training_date']?.toString() ?? '') ??
          DateTime(1900);
      final bDate =
          DateTime.tryParse(bPlan['training_date']?.toString() ?? '') ??
          DateTime(1900);
      return aDate.compareTo(bDate);
    });

    var present = 0;
    var excused = 0;
    var absent = 0;
    var attendedMinutes = 0;

    final tableData = <List<String>>[
      ['Datum', 'Thema', 'Zeit', 'Status', 'Bemerkung'],
    ];

    for (final record in records) {
      final plan = record['plan'] as Map<String, dynamic>;
      final status = record['status']?.toString() ?? '';
      final start = _minutes(plan['start_time']);
      final end = _minutes(plan['end_time']);

      if (status == 'anwesend') {
        present++;
        if (start != null && end != null && end > start) {
          attendedMinutes += end - start;
        }
      } else if (status == 'entschuldigt') {
        excused++;
      } else if (status == 'abwesend') {
        absent++;
      }

      final topic =
          plan['topic']?.toString().trim().isNotEmpty == true
              ? plan['topic'].toString()
              : plan['title']?.toString() ?? 'Ausbildung';

      final startText = _time(plan['start_time']);
      final endText = _time(plan['end_time']);
      final timeText =
          startText == '-'
              ? '-'
              : endText == '-'
              ? startText
              : '$startText-$endText';

      tableData.add([
        _date(plan['training_date']),
        topic,
        timeText,
        _trainingStatus(status),
        record['note']?.toString().trim() ?? '',
      ]);
    }

    final total = records.length;
    final percent = total == 0 ? 0 : ((present / total) * 100).round();
    final hours = attendedMinutes / 60;

    final pdf = pw.Document();
    final logo = await _loadLogo();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) =>
            _pdfHeader(context, logo, 'Ausbildungsnachweis'),
        footer: _pdfFooter,
        build: (context) => [
          pw.SizedBox(height: 8),
          pw.Text(
            'Ausbildungsnachweis',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xff0a1f44),
            ),
          ),
          pw.SizedBox(height: 10),
          _pdfKeyValueTable([
            ['Jugendmitglied', _name(youth)],
            ['Zeitraum', _selectedYear?.toString() ?? 'Alle Jahre'],
            ['Erfasste Ausbildungen', '$total'],
            ['Anwesend', '$present'],
            ['Entschuldigt', '$excused'],
            ['Abwesend', '$absent'],
            ['Anwesenheitsquote', '$percent %'],
            [
              'Besuchte Ausbildungszeit',
              '${hours.toStringAsFixed(hours % 1 == 0 ? 0 : 1)} Stunden',
            ],
          ]),
          _pdfSectionTitle('Ausbildungen'),
          if (tableData.length == 1)
            pw.Text(
              'Für diesen Zeitraum wurden noch keine Anwesenheiten erfasst.',
              style: const pw.TextStyle(fontSize: 10),
            )
          else
            pw.TableHelper.fromTextArray(
              data: tableData,
              headerCount: 1,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xff0a1f44),
              ),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellPadding: const pw.EdgeInsets.all(4),
              border: pw.TableBorder.all(
                color: const PdfColor.fromInt(0xffd9e0e7),
                width: 0.5,
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.0),
                1: pw.FlexColumnWidth(2.2),
                2: pw.FlexColumnWidth(1.1),
                3: pw.FlexColumnWidth(1.2),
                4: pw.FlexColumnWidth(2.0),
              },
            ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Dieser Nachweis wurde aus den in der App erfassten Anwesenheitsdaten erstellt.',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColor.fromInt(0xff667085),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> _buildMaterialReport() async {
    final youth = _selectedYouth;
    if (youth == null) throw Exception('Bitte ein Jugendmitglied auswählen.');

    final youthId = youth['id'].toString();

    final result = await Future.wait([
      _supabase
          .from('material_assignments')
          .select()
          .eq('youth_id', youthId)
          .order('issued_at', ascending: false),
      _supabase.from('material_items').select().order('name'),
    ]);

    final assignments = List<Map<String, dynamic>>.from(result[0]);
    final items = List<Map<String, dynamic>>.from(result[1]);

    final itemById = <String, Map<String, dynamic>>{
      for (final item in items) item['id'].toString(): item,
    };

    final tableData = <List<String>>[
      ['Material', 'Menge', 'Ausgabe', 'Rückgabe geplant', 'Zurück', 'Status'],
    ];

    var activeCount = 0;

    for (final row in assignments) {
      final item = itemById[row['material_id']?.toString()];
      if (item == null) continue;

      final active = row['returned_at'] == null;
      if (active) activeCount++;

      tableData.add([
        item['name']?.toString() ?? 'Material',
        ((row['quantity'] as num?)?.toInt() ?? 0).toString(),
        _date(row['issued_at']),
        _date(row['due_back_at']),
        _date(row['returned_at']),
        active ? 'Ausgegeben' : 'Zurückgegeben',
      ]);
    }

    final pdf = pw.Document();
    final logo = await _loadLogo();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) =>
            _pdfHeader(context, logo, 'Materialausgabe'),
        footer: _pdfFooter,
        build: (context) => [
          pw.SizedBox(height: 8),
          pw.Text(
            'Materialausgabe',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xff0a1f44),
            ),
          ),
          pw.SizedBox(height: 10),
          _pdfKeyValueTable([
            ['Jugendmitglied', _name(youth)],
            ['Offene Ausgaben', '$activeCount'],
            ['Gesamte Ausgaben im Verlauf', '${assignments.length}'],
          ]),
          _pdfSectionTitle('Ausgabeübersicht'),
          if (tableData.length == 1)
            pw.Text(
              'Für dieses Jugendmitglied wurde noch kein Material ausgegeben.',
              style: const pw.TextStyle(fontSize: 10),
            )
          else
            pw.TableHelper.fromTextArray(
              data: tableData,
              headerCount: 1,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xff0a1f44),
              ),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellPadding: const pw.EdgeInsets.all(4),
              border: pw.TableBorder.all(
                color: const PdfColor.fromInt(0xffd9e0e7),
                width: 0.5,
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.0),
                1: pw.FlexColumnWidth(0.65),
                2: pw.FlexColumnWidth(1.1),
                3: pw.FlexColumnWidth(1.25),
                4: pw.FlexColumnWidth(1.1),
                5: pw.FlexColumnWidth(1.25),
              },
            ),
          pw.SizedBox(height: 32),
          pw.Row(
            children: [
              pw.Expanded(
                child: _signatureLine('Ausgegeben / geprüft durch'),
              ),
              pw.SizedBox(width: 24),
              pw.Expanded(
                child: _signatureLine(
                  'Jugendmitglied / Erziehungsberechtigte',
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _signatureLine(String label) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 26),
        pw.Container(
          height: 0.7,
          color: const PdfColor.fromInt(0xff667085),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          label,
          style: const pw.TextStyle(
            fontSize: 8,
            color: PdfColor.fromInt(0xff667085),
          ),
        ),
      ],
    );
  }

  Future<Uint8List> _buildMemberRecordPdf() async {
    final youth = _selectedYouth;
    if (youth == null) throw Exception('Bitte ein Jugendmitglied auswählen.');

    final record = await _loadMemberRecord(youth['id'].toString());
    if (record == null) {
      throw Exception('Für dieses Jugendmitglied ist noch kein Stammblatt angelegt.');
    }

    String text(dynamic value) {
      final result = value?.toString().trim() ?? '';
      return result.isEmpty ? '-' : result;
    }

    final pdf = pw.Document();
    final logo = await _loadLogo();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) =>
            _pdfHeader(context, logo, 'Stammdatenblatt'),
        footer: _pdfFooter,
        build: (context) => [
          pw.SizedBox(height: 8),
          pw.Text(
            'Stammdatenblatt',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xff0a1f44),
            ),
          ),
          _pdfSectionTitle('Persönliche Angaben'),
          _pdfKeyValueTable([
            ['Vorname', youth['first_name']?.toString() ?? '-'],
            ['Name', youth['last_name']?.toString() ?? '-'],
            ['Geburtsdatum', _date(record['birth_date'])],
            ['Krankenkasse', text(record['health_insurance'])],
            ['Straße', text(record['street'])],
            ['PLZ / Ort', '${text(record['postal_code'])} ${text(record['city'])}'],
            ['E-Mail', text(record['email'])],
            ['Allergien', text(record['allergies'])],
          ]),
          _pdfSectionTitle('Notfallkontakte'),
          _pdfKeyValueTable([
            [
              'Kontakt 1',
              '${text(record['emergency_contact_name'])} - '
                  '${text(record['emergency_contact_phone'])}',
            ],
            [
              'Kontakt 2',
              '${text(record['emergency_contact_2_name'])} - '
                  '${text(record['emergency_contact_2_phone'])}',
            ],
            [
              'Kontakt 3',
              '${text(record['emergency_contact_3_name'])} - '
                  '${text(record['emergency_contact_3_phone'])}',
            ],
            [
              'Kontakt 4',
              '${text(record['emergency_contact_4_name'])} - '
                  '${text(record['emergency_contact_4_phone'])}',
            ],
          ]),
          _pdfSectionTitle('Heimweg und Gruppenbewegung'),
          _pdfKeyValueTable([
            ['Heimweg', _homeWayLabel(record['home_way'])],
            ['Telefon bei Abholung', text(record['pickup_phone'])],
            ['Bemerkung Heimweg', text(record['home_way_notes'])],
            [
              'Selbstständige Gruppenbewegung',
              _boolLabel(record['group_movement_allowed']),
            ],
            [
              'Bemerkung Gruppenbewegung',
              text(record['group_movement_notes']),
            ],
          ]),
          _pdfSectionTitle('Schwimmen und Baden'),
          _pdfKeyValueTable([
            ['Teilnahme erlaubt', _boolLabel(record['swimming_allowed'])],
            ['Schwimmstatus', _swimmingLabel(record['swimming_level'])],
            ['Schwimmstufe', text(record['swimming_stage'])],
            ['Bemerkung', text(record['swimming_notes'])],
          ]),
          _pdfSectionTitle('Foto, Video und Medien'),
          _pdfKeyValueTable([
            [
              'Foto- / Videoaufnahmen',
              _boolLabel(record['media_recording_allowed']),
            ],
            [
              'Veröffentlichung',
              _boolLabel(record['media_publication_allowed']),
            ],
            ['Bemerkung', text(record['media_notes'])],
          ]),
          _pdfSectionTitle('Weitere interne Angaben'),
          _pdfKeyValueTable([
            ['Eintrittsdatum', _date(record['entry_date'])],
            ['Mitglieds- / Dienstnummer', text(record['membership_number'])],
            ['Kleidergröße', text(record['clothing_size'])],
            ['Helmgröße', text(record['helmet_size'])],
            ['Erziehungsberechtigte', text(record['guardian_name'])],
            ['Telefon', text(record['guardian_phone'])],
            ['E-Mail', text(record['guardian_email'])],
            ['Stand des Stammblatts', _date(record['record_as_of'])],
            ['Interne Bemerkungen', text(record['notes'])],
          ]),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _checkRow({
    required String label,
    required bool? value,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 145,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          _checkbox('Ja', value == true),
          pw.SizedBox(width: 16),
          _checkbox('Nein', value == false),
          pw.SizedBox(width: 16),
          _checkbox('offen', value == null),
        ],
      ),
    );
  }

  pw.Widget _checkbox(String label, bool checked) {
    return pw.Row(
      children: [
        pw.Container(
          width: 11,
          height: 11,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              color: const PdfColor.fromInt(0xff4b5563),
              width: 0.8,
            ),
          ),
          child:
              checked
                  ? pw.Text(
                    'X',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  )
                  : null,
        ),
        pw.SizedBox(width: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 8.5)),
      ],
    );
  }

  Future<Uint8List> _buildConsentForm() async {
    final youth = _selectedYouth;
    if (youth == null) throw Exception('Bitte ein Jugendmitglied auswählen.');

    final record = await _loadMemberRecord(youth['id'].toString());

    final pdf = pw.Document();
    final logo = await _loadLogo();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) =>
            _pdfHeader(context, logo, 'Einverständniserklärung'),
        footer: _pdfFooter,
        build: (context) => [
          pw.SizedBox(height: 8),
          pw.Text(
            'Einverständniserklärung',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xff0a1f44),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'für die Teilnahme an Aktivitäten der Jugendfeuerwehr '
            'Seehausen/Kyffhäuser',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 14),
          _pdfKeyValueTable([
            ['Jugendmitglied', _name(youth)],
            ['Geburtsdatum', _date(record?['birth_date'])],
          ]),
          _pdfSectionTitle('Heimweg'),
          pw.Text(
            'Das Jugendmitglied darf nach Ende des Dienstes:',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 7),
          pw.Row(
            children: [
              _checkbox(
                'selbstständig nach Hause gehen',
                record?['home_way']?.toString() == 'selbststaendig',
              ),
              pw.SizedBox(width: 18),
              _checkbox(
                'wird abgeholt',
                record?['home_way']?.toString() == 'abholung',
              ),
            ],
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            'Telefon bei Abholung: ${record?['pickup_phone']?.toString().trim().isNotEmpty == true ? record!['pickup_phone'] : '________________________'}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          _pdfSectionTitle('Selbstständiges Bewegen in einer Gruppe'),
          _checkRow(
            label: 'In einer Gruppe erlaubt',
            value: record?['group_movement_allowed'] as bool?,
          ),
          _pdfSectionTitle('Schwimmen und Baden'),
          _checkRow(
            label: 'Teilnahme erlaubt',
            value: record?['swimming_allowed'] as bool?,
          ),
          pw.Text(
            'Schwimmstatus: '
            '${record == null ? '________________________' : _swimmingLabel(record['swimming_level'])}'
            '${record?['swimming_stage']?.toString().trim().isNotEmpty == true ? ' - ${record!['swimming_stage']}' : ''}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          _pdfSectionTitle('Foto, Video und Veröffentlichung'),
          _checkRow(
            label: 'Foto- / Videoaufnahmen',
            value: record?['media_recording_allowed'] as bool?,
          ),
          _checkRow(
            label: 'Veröffentlichung erlaubt',
            value: record?['media_publication_allowed'] as bool?,
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Mit meiner Unterschrift bestätige ich die oben gemachten Angaben. '
            'Änderungen teile ich der Jugendfeuerwehr zeitnah mit.',
            style: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
          ),
          pw.SizedBox(height: 34),
          pw.Row(
            children: [
              pw.Expanded(child: _signatureLine('Ort / Datum')),
              pw.SizedBox(width: 24),
              pw.Expanded(
                child: _signatureLine('Erziehungsberechtigte Person'),
              ),
            ],
          ),
          pw.SizedBox(height: 26),
          pw.Row(
            children: [
              pw.Expanded(
                child: _signatureLine('Jugendmitglied, sofern vorgesehen'),
              ),
              pw.SizedBox(width: 24),
              pw.Expanded(child: _signatureLine('Ausbilder / geprüft durch')),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> _runPdfAction({
    required Future<Uint8List> Function() builder,
    required String filename,
    required bool print,
  }) async {
    if (_working) return;

    if (_selectedYouth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte ein Jugendmitglied auswählen.')),
      );
      return;
    }

    final allowed = await _confirmPersonalData();
    if (!allowed) return;

    setState(() => _working = true);

    try {
      final bytes = await builder();

      if (print) {
        await Printing.layoutPdf(
          name: filename,
          onLayout: (_) async => bytes,
        );
      } else {
        await Printing.sharePdf(
          bytes: bytes,
          filename: filename,
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _documentCard({
    required IconData icon,
    required String title,
    required String description,
    required Future<Uint8List> Function() builder,
    required String filename,
    Color accent = _blue,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE3E8EE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFF667085),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _working
                          ? null
                          : () => _runPdfAction(
                            builder: builder,
                            filename: filename,
                            print: false,
                          ),
                  icon: const Icon(Icons.ios_share_outlined),
                  label: const Text('PDF teilen'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _working
                          ? null
                          : () => _runPdfAction(
                            builder: builder,
                            filename: filename,
                            print: true,
                          ),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Drucken'),
                ),
              ),
            ],
          ),
        ],
      ),
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

    final youthName = _safeFileName(_name(_selectedYouth));

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Formulare & PDF'),
        actions: [
          IconButton(
            tooltip: 'Zur Startseite',
            onPressed: () => HomeNavigation.goHome(context),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
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
                    Icons.picture_as_pdf_outlined,
                    color: Colors.white,
                    size: 34,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Nachweise und Formulare direkt aus den vorhandenen App-Daten erstellen',
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
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: _red),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedYouthId,
              decoration: const InputDecoration(
                labelText: 'Jugendmitglied',
                prefixIcon: Icon(Icons.person_outline),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
              items:
                  _youth
                      .map(
                        (youth) => DropdownMenuItem<String>(
                          value: youth['id'].toString(),
                          child: Text(_name(youth)),
                        ),
                      )
                      .toList(),
              onChanged:
                  _working
                      ? null
                      : (value) {
                        setState(() => _selectedYouthId = value);
                      },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _selectedYear,
              decoration: const InputDecoration(
                labelText: 'Jahr für Ausbildungsnachweis',
                prefixIcon: Icon(Icons.calendar_month_outlined),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Alle Jahre'),
                ),
                ..._years.map(
                  (year) => DropdownMenuItem<int?>(
                    value: year,
                    child: Text('$year'),
                  ),
                ),
              ],
              onChanged:
                  _working
                      ? null
                      : (value) {
                        setState(() => _selectedYear = value);
                      },
            ),
            if (_working) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 18),
            _documentCard(
              icon: Icons.fact_check_outlined,
              title: 'Ausbildungsnachweis',
              description:
                  'Anwesenheit, besuchte Ausbildungszeit, Status und Bemerkungen '
                  'für das gewählte Jahr oder alle Jahre.',
              builder: _buildTrainingCertificate,
              filename:
                  'Ausbildungsnachweis_${youthName}_${_selectedYear ?? 'gesamt'}.pdf',
              accent: _green,
            ),
            _documentCard(
              icon: Icons.inventory_2_outlined,
              title: 'Materialausgabe',
              description:
                  'Alle Materialausgaben, offene Rückgaben und der bisherige '
                  'Ausgabeverlauf des Jugendmitglieds mit Unterschriftsfeldern.',
              builder: _buildMaterialReport,
              filename: 'Materialausgabe_${youthName}.pdf',
              accent: _orange,
            ),
            _documentCard(
              icon: Icons.badge_outlined,
              title: 'Stammdatenblatt',
              description:
                  'Digitales Stammblatt mit persönlichen Daten, Notfallkontakten, '
                  'Heimweg, Schwimm- und Medienfreigaben.',
              builder: _buildMemberRecordPdf,
              filename: 'Stammdatenblatt_${youthName}.pdf',
              accent: _red,
            ),
            _documentCard(
              icon: Icons.draw_outlined,
              title: 'Einverständniserklärung',
              description:
                  'Druckbare Vorlage für Heimweg, Gruppenbewegung, Schwimmen, '
                  'Foto/Video und Veröffentlichung mit Unterschriftsfeldern.',
              builder: _buildConsentForm,
              filename: 'Einverstaendniserklaerung_${youthName}.pdf',
              accent: _blue,
            ),
          ],
        ),
      ),
    );
  }
}
