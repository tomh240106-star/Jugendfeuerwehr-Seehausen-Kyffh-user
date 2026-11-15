import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CashManagementScreen extends StatefulWidget {
  const CashManagementScreen({super.key});

  @override
  State<CashManagementScreen> createState() => _CashManagementScreenState();
}

class _CashManagementScreenState extends State<CashManagementScreen> {
  final _db = Supabase.instance.client;
  final _currency = NumberFormat.currency(locale: 'de_DE', symbol: '€');
  final _date = DateFormat('dd.MM.yyyy');
  bool _loading = true;
  bool _authorized = false;
  String? _error;
  List<Map<String, dynamic>> _entries = [];
  int? _year;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _amount(Map<String, dynamic> entry) => (entry['amount_cents'] as num).toInt();
  int get _balance => _entries.fold(0, (sum, e) => sum + (e['kind'] == 'income' ? _amount(e) : -_amount(e)));
  int get _income => _filtered.where((e) => e['kind'] == 'income').fold(0, (sum, e) => sum + _amount(e));
  int get _expenses => _filtered.where((e) => e['kind'] == 'expense').fold(0, (sum, e) => sum + _amount(e));
  List<Map<String, dynamic>> get _filtered => _year == null ? _entries : _entries.where((e) => DateTime.parse(e['booked_on'].toString()).year == _year).toList();
  String _money(int cents) => _currency.format(cents / 100);
  String _moneyPdf(int cents) => '${(cents / 100).toStringAsFixed(2)} EUR';

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final access = await _db.rpc('is_cashier');
      if (access != true) {
        if (mounted) setState(() { _authorized = false; _loading = false; });
        return;
      }
      final rows = await _db.from('cash_ledger').select('id,booked_on,kind,amount_cents,category,description,receipt_reference,created_at').order('booked_on', ascending: false).order('created_at', ascending: false);
      if (mounted) setState(() {
        _authorized = true;
        _entries = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _addEntry() async {
    final form = GlobalKey<FormState>();
    final amount = TextEditingController();
    final category = TextEditingController();
    final description = TextEditingController();
    final receipt = TextEditingController();
    var kind = 'income';
    var bookedOn = DateTime.now();
    var saving = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Neue Kassenbuchung'),
            content: SizedBox(width: 420, child: SingleChildScrollView(child: Form(
              key: form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Buchungsart'),
                  items: const [DropdownMenuItem(value: 'income', child: Text('Einnahme')), DropdownMenuItem(value: 'expense', child: Text('Ausgabe'))],
                  onChanged: saving ? null : (value) => setDialogState(() => kind = value ?? 'income'),
                ),
                TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Betrag in Euro (z. B. 12,50)'), validator: (v) {
                  final parsed = double.tryParse((v ?? '').trim().replaceAll('.', '').replaceAll(',', '.'));
                  if (parsed == null || parsed <= 0 || !parsed.isFinite) return 'Gültigen Betrag eingeben';
                  return null;
                }),
                TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Kategorie'), validator: (v) => (v ?? '').trim().isEmpty ? 'Kategorie fehlt' : null),
                TextFormField(controller: description, decoration: const InputDecoration(labelText: 'Beschreibung'), maxLines: 2, validator: (v) => (v ?? '').trim().isEmpty ? 'Beschreibung fehlt' : null),
                TextFormField(controller: receipt, decoration: const InputDecoration(labelText: 'Belegnummer / Referenz (optional)')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: saving ? null : () async {
                    final chosen = await showDatePicker(context: context, initialDate: bookedOn, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (chosen != null) setDialogState(() => bookedOn = chosen);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('Datum: ${_date.format(bookedOn)}'),
                ),
              ]),
            ))),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Abbrechen')),
              FilledButton(onPressed: saving ? null : () async {
                if (!(form.currentState?.validate() ?? false)) return;
                final raw = amount.text.trim().replaceAll('.', '').replaceAll(',', '.');
                final cents = (double.parse(raw) * 100).round();
                if (cents <= 0) return;
                setDialogState(() => saving = true);
                try {
                  await _db.from('cash_ledger').insert({
                    'booked_on': DateFormat('yyyy-MM-dd').format(bookedOn),
                    'kind': kind,
                    'amount_cents': cents,
                    'category': category.text.trim(),
                    'description': description.text.trim(),
                    'receipt_reference': receipt.text.trim().isEmpty ? null : receipt.text.trim(),
                    'created_by': _db.auth.currentUser!.id,
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _load();
                } catch (e) {
                  if (dialogContext.mounted) {
                    setDialogState(() => saving = false);
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Buchung fehlgeschlagen: $e')));
                  }
                }
              }, child: Text(saving ? 'Speichert ...' : 'Buchen')),
            ],
          );
        }),
      );
    } finally {
      amount.dispose(); category.dispose(); description.dispose(); receipt.dispose();
    }
  }

  Future<void> _exportPdf() async {
    final entries = _filtered;
    final doc = pw.Document();
    final selected = _year == null ? 'Gesamtübersicht' : 'Jahr $_year';
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Text('Jugendfeuerwehr Seehausen – Kassenbericht', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Text(selected),
        pw.Text('Einnahmen: ${_moneyPdf(_income)}    Ausgaben: ${_moneyPdf(_expenses)}'),
        pw.Text('Gesamtkassenbestand: ${_moneyPdf(_balance)}'),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Datum', 'Art', 'Kategorie / Beschreibung', 'Betrag'],
          data: entries.map((e) => [
            _date.format(DateTime.parse(e['booked_on'].toString())),
            e['kind'] == 'income' ? 'Einnahme' : 'Ausgabe',
            '${e['category']} - ${e['description']}${e['receipt_reference'] == null ? '' : ' (Beleg: ${e['receipt_reference']})'}',
            '${e['kind'] == 'income' ? '+' : '-'}${_moneyPdf(_amount(e))}',
          ]).toList(),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'Kassenbericht_Seehausen_${_year ?? 'gesamt'}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final years = _entries.map((e) => DateTime.parse(e['booked_on'].toString()).year).toSet().toList()..sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: AppBar(title: const Text('Kassenverwaltung'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Aktualisieren')]),
      floatingActionButton: _authorized && !_loading ? FloatingActionButton.extended(onPressed: _addEntry, icon: const Icon(Icons.add), label: const Text('Buchung')) : null,
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Kassendaten konnten nicht geladen werden:\n$_error'))) : !_authorized ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Kein Zugriff. Ein Administrator muss dich als Kassenwart freischalten.'))) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Aktueller Kassenbestand'),
            const SizedBox(height: 8),
            Text(_money(_balance), style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text('Einnahmen (${_year ?? 'alle Jahre'}): ${_money(_income)}'),
            Text('Ausgaben (${_year ?? 'alle Jahre'}): ${_money(_expenses)}'),
          ]))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: DropdownButtonFormField<int?>(
              initialValue: _year,
              decoration: const InputDecoration(labelText: 'Zeitraum', border: OutlineInputBorder()),
              items: [const DropdownMenuItem<int?>(value: null, child: Text('Alle Jahre')), ...years.map((y) => DropdownMenuItem<int?>(value: y, child: Text('$y')))],
              onChanged: (value) => setState(() => _year = value),
            )),
            const SizedBox(width: 8),
            IconButton(onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'PDF-Kassenbericht'),
          ]),
          const SizedBox(height: 18),
          Text('Kassenbuch (${_filtered.length} Buchungen)', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_filtered.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Noch keine Buchungen vorhanden.')),
          ..._filtered.map((e) => Card(child: ListTile(
            leading: Icon(e['kind'] == 'income' ? Icons.arrow_downward : Icons.arrow_upward, color: e['kind'] == 'income' ? Colors.green : Colors.red),
            title: Text(e['description'].toString()),
            subtitle: Text('${_date.format(DateTime.parse(e['booked_on'].toString()))} · ${e['category']}${e['receipt_reference'] == null ? '' : '\nBeleg: ${e['receipt_reference']}'}'),
            isThreeLine: e['receipt_reference'] != null,
            trailing: Text('${e['kind'] == 'income' ? '+' : '−'}${_money(_amount(e))}', style: TextStyle(fontWeight: FontWeight.bold, color: e['kind'] == 'income' ? Colors.green : null)),
          ))),
          const SizedBox(height: 12),
          const Text('Hinweis: Buchungen können aus Nachvollziehbarkeitsgründen nicht gelöscht werden. Korrekturen erfolgen als Gegenbuchung.', style: TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}
