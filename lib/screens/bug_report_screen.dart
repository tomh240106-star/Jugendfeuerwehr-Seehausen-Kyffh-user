import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  static const _navy = Color(0xFF06111F);
  static const _panel = Color(0xFF0C2133);
  static const _blue = Color(0xFF00A8FF);
  static const _red = Color(0xFFE30613);

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _supabase = Supabase.instance.client;
  bool _sending = false;
  String _area = 'Startseite';

  static const _areas = <String>[
    'Startseite',
    'Termine',
    'Ausbildungspläne',
    'Anwesenheit',
    'Nachrichten',
    'Dokumente',
    'Projekte',
    'Alarm',
    'Mitgliederverwaltung',
    'Stammblätter',
    'Materialverwaltung',
    'Formulare & PDF',
    'Profil / Mehr',
    'Update',
    'Sonstiges',
  ];

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = _supabase.auth.currentUser;
    final title = _title.text.trim();
    final description = _description.text.trim();
    if (user == null) return;
    if (title.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Titel und Beschreibung ausfüllen.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await _supabase.from('user_bug_reports').insert({
        'user_id': user.id,
        'title': title,
        'description': description,
        'app_area': _area,
        'status': 'new',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehlermeldung wurde an den Entwickler gesendet.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Senden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Fehler melden'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _blue.withValues(alpha: .35)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.help_outline_rounded, color: _blue, size: 30),
                  SizedBox(width: 10),
                  Expanded(child: Text('Problem oder Fehler gefunden?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                ]),
                SizedBox(height: 8),
                Text('Beschreibe kurz, was passiert ist. Die Meldung wird zentral an den Entwickler übermittelt.', style: TextStyle(color: Color(0xFFB6C3D1), height: 1.35)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Theme(
            data: Theme.of(context).copyWith(
              canvasColor: _panel,
              textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
            ),
            child: DropdownButtonFormField<String>(
            initialValue: _selectedArea,
            isExpanded: true,
            dropdownColor: _panel,
            iconEnabledColor: Colors.white,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: const InputDecoration(
              labelText: 'Betroffener Bereich',
              prefixIcon: Icon(Icons.apps_rounded, color: _blue),
            ),
            items: _areas
                .map(
                  (area) => DropdownMenuItem<String>(
                    value: area,
                    child: Text(
                      area,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                )
                .toList(),
            selectedItemBuilder: (context) => _areas
                .map((area) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text(area, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ))
                .toList(),
            onChanged: _sending
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _area = value);
                  },
            ),
          ),
          const SizedBox(height: 14),
          TextField(controller: _title, maxLength: 120, decoration: const InputDecoration(labelText: 'Kurzer Titel', hintText: 'z. B. Dokument lässt sich nicht öffnen')),
          const SizedBox(height: 8),
          TextField(controller: _description, minLines: 5, maxLines: 9, maxLength: 3000, decoration: const InputDecoration(labelText: 'Beschreibung', hintText: 'Was hast du gemacht und was ist danach passiert?')),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _sending ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: _red, padding: const EdgeInsets.symmetric(vertical: 15)),
            icon: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
            label: Text(_sending ? 'Wird gesendet …' : 'Fehler melden'),
          ),
        ],
      ),
    );
  }
}
