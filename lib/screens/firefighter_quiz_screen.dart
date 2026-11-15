import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FirefighterQuizScreen extends StatefulWidget {
  const FirefighterQuizScreen({super.key});
  @override
  State<FirefighterQuizScreen> createState() => _FirefighterQuizScreenState();
}

class _FirefighterQuizScreenState extends State<FirefighterQuizScreen> {
  final db = Supabase.instance.client;
  static const red = Color(0xFFE30613);
  bool loading = true, trainer = false, busy = false;
  List<Map<String, dynamic>> questions = [];
  Map<String, dynamic>? session;
  Map<String, dynamic>? currentQuestion;
  int? chosen;
  bool? correct;
  String? error;
  Timer? ticker;
  String category = 'Alle';
  String difficulty = 'Alle';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = db.auth.currentUser!.id;
      final p = await db.from('profiles').select('role').eq('id', uid).single();
      final q = await db.from('fw_quiz_questions').select().order('category');
      if (!mounted) return;
      setState(() {
        trainer = p['role'] == 'ausbilder';
        questions = (q as List).map((e) => Map<String, dynamic>.from(e)).toList();
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() { loading = false; error = 'Laden fehlgeschlagen: $e'; });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try { await action(); }
    catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  List<Map<String, dynamic>> get filtered => questions.where((q) =>
    q['active'] == true && (category == 'Alle' || q['category'] == category) &&
    (difficulty == 'Alle' || q['difficulty'] == difficulty)).toList();

  Future<void> _start(String mode) async {
    final items = [...filtered]..shuffle(Random());
    if (items.isEmpty) { setState(() => error = 'Keine Fragen für diese Auswahl vorhanden.'); return; }
    await _run(() async {
      final result = await db.rpc('fw_quiz_start', params: {
        'p_title': mode == 'solo' ? 'Mein Wissenstest' : 'Gemeinsamer Wissenstest',
        'p_mode': mode,
        'p_question_ids': items.take(10).map((e) => e['id'] as String).toList(),
      });
      await _setSession(Map<String, dynamic>.from(result as Map));
    });
  }

  Future<void> _join() async {
    final c = TextEditingController();
    final code = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Gruppentest beitreten'),
      content: TextField(controller: c, maxLength: 6, textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Teilnahmecode')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim().toUpperCase()), child: const Text('Beitreten'))],
    ));
    c.dispose();
    if (code == null || code.isEmpty) return;
    await _run(() async {
      final data = await db.from('fw_quiz_sessions').select().eq('code', code).eq('mode', 'group').maybeSingle();
      if (data == null) throw Exception('Kein Gruppentest mit diesem Code gefunden.');
      await _setSession(Map<String, dynamic>.from(data));
    });
  }

  Future<void> _setSession(Map<String, dynamic> s) async {
    session = s;
    chosen = null; correct = null;
    await _refreshQuestion();
    ticker?.cancel();
    if (s['mode'] == 'group') {
      ticker = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    }
    if (mounted) setState(() {});
  }

  bool polling = false;
  Future<void> _poll() async {
    if (polling || session == null || session!['mode'] != 'group') return;
    polling = true;
    try {
      final latest = await db.from('fw_quiz_sessions').select().eq('id', session!['id']).single();
      if (!mounted || session == null) return;
      final changed = latest['current_index'] != session!['current_index'] || latest['status'] != session!['status'];
      session = Map<String, dynamic>.from(latest);
      if (changed) { chosen = null; correct = null; await _refreshQuestion(); }
      if (mounted && changed) setState(() {});
      if (latest['status'] == 'finished') { ticker?.cancel(); if (mounted) setState(() {}); }
    } catch (_) { /* Retry on next tick. */ }
    finally { polling = false; }
  }

  Future<void> _refreshQuestion() async {
    if (session == null || session!['status'] != 'active') { currentQuestion = null; return; }
    final ids = (session!['question_ids'] as List).cast<String>();
    final index = session!['current_index'] as int;
    if (index >= ids.length) { currentQuestion = null; return; }
    final q = await db.from('fw_quiz_questions').select().eq('id', ids[index]).single();
    currentQuestion = Map<String, dynamic>.from(q);
    final previous = await db.from('fw_quiz_answers').select('selected_index,is_correct')
      .eq('session_id', session!['id']).eq('user_id', db.auth.currentUser!.id)
      .eq('question_id', ids[index]).maybeSingle();
    chosen = previous?['selected_index'] as int?;
    correct = previous?['is_correct'] as bool?;
  }

  Future<void> _answer(int index) async {
    if (chosen != null || session == null) return;
    await _run(() async {
      final ok = await db.rpc('fw_quiz_answer', params: {
        'p_session_id': session!['id'], 'p_selected_index': index,
      });
      if (mounted) setState(() { chosen = index; correct = ok == true; });
    });
  }

  Future<void> _advance() async {
    if (session == null) return;
    await _run(() async {
      final fn = session!['mode'] == 'solo' ? 'fw_quiz_solo_next' : 'fw_quiz_advance';
      final result = await db.rpc(fn, params: {'p_session_id': session!['id']});
      await _setSession(Map<String, dynamic>.from(result as Map));
    });
  }

  Future<void> _results() async {
    if (session == null) return;
    await _run(() async {
      final a = await db.from('fw_quiz_answers').select('user_id,is_correct')
        .eq('session_id', session!['id']);
      final scores = <String, List<int>>{};
      for (final item in a as List) {
        final id = item['user_id'] as String;
        final count = scores.putIfAbsent(id, () => [0, 0]);
        count[1]++;
        if (item['is_correct'] == true) count[0]++;
      }
      if (!mounted) return;
      final own = db.auth.currentUser!.id;
      final isOwner = session!['created_by'] == own;
      final entries = scores.entries.where((e) =>
        session!['mode'] == 'solo' || (trainer && isOwner) || e.key == own).toList()
        ..sort((a, b) => b.value[0].compareTo(a.value[0]));
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Testergebnisse'),
        content: SizedBox(width: 350, child: entries.isEmpty
          ? const Text('Noch keine Antworten vorhanden.')
          : Column(mainAxisSize: MainAxisSize.min, children: entries.map((e) {
              final name = e.key == own ? 'Du' : 'Teilnehmer ${e.key.substring(0, 8)}';
              final total = (session!['question_ids'] as List).length;
              return ListTile(title: Text(name), subtitle: Text('${e.value[0]} von $total richtig · ${total == 0 ? 0 : (100 * e.value[0] / total).round()} %'));
            }).toList())),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
      ));
    });
  }

  Future<void> _editQuestion([Map<String, dynamic>? existing]) async {
    final title = TextEditingController(text: existing?['question']?.toString() ?? '');
    final cat = TextEditingController(text: existing?['category']?.toString() ?? 'Allgemein');
    final explain = TextEditingController(text: existing?['explanation']?.toString() ?? '');
    final old = existing?['options'] is List ? existing!['options'] as List : <dynamic>[];
    final opts = List.generate(4, (i) => TextEditingController(text: i < old.length ? '${old[i]}' : ''));
    var right = existing?['correct_index'] as int? ?? 0;
    var level = existing?['difficulty']?.toString() ?? 'leicht';
    final saved = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
      title: Text(existing == null ? 'Neue Frage' : 'Frage bearbeiten'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, maxLines: 2, decoration: const InputDecoration(labelText: 'Frage')),
        TextField(controller: cat, decoration: const InputDecoration(labelText: 'Kategorie')),
        DropdownButtonFormField<String>(initialValue: level, decoration: const InputDecoration(labelText: 'Schwierigkeit'),
          items: ['leicht','mittel','schwer'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => update(() => level = v ?? 'leicht')),
        for (var i = 0; i < 4; i++) TextField(controller: opts[i], decoration: InputDecoration(labelText: 'Antwort ${i+1}')),
        DropdownButtonFormField<int>(initialValue: right, decoration: const InputDecoration(labelText: 'Richtige Antwort'),
          items: List.generate(4, (i) => DropdownMenuItem(value: i, child: Text('Antwort ${i+1}'))),
          onChanged: (v) => update(() => right = v ?? 0)),
        TextField(controller: explain, maxLines: 2, decoration: const InputDecoration(labelText: 'Erklärung')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () {
          if (title.text.trim().isEmpty || cat.text.trim().isEmpty || opts.any((o) => o.text.trim().isEmpty)) {
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Bitte alle Fragen- und Antwortfelder ausfüllen.')));
            return;
          }
          Navigator.pop(ctx, true);
        }, child: const Text('Speichern'))],
    )));
    if (saved == true) {
      await _run(() async {
        final data = <String, dynamic>{'question': title.text.trim(), 'category': cat.text.trim(),
          'difficulty': level, 'options': opts.map((e) => e.text.trim()).toList(),
          'correct_index': right, 'explanation': explain.text.trim()};
        if (existing == null) {
          data['created_by'] = db.auth.currentUser!.id;
          await db.from('fw_quiz_questions').insert(data);
        } else { await db.from('fw_quiz_questions').update(data).eq('id', existing['id']); }
        await _load();
      });
    }
    title.dispose(); cat.dispose(); explain.dispose(); for (final o in opts) { o.dispose(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Feuerwehr-Wissenstest'), backgroundColor: red, foregroundColor: Colors.white,
      actions: [if (session != null) IconButton(tooltip: 'Zur Übersicht', onPressed: () {
        ticker?.cancel(); setState(() { session = null; currentQuestion = null; chosen = null; });
      }, icon: const Icon(Icons.home_outlined))]),
      body: loading ? const Center(child: CircularProgressIndicator()) :
      RefreshIndicator(onRefresh: session == null ? _load : _poll, child: ListView(padding: const EdgeInsets.all(16), children: [
        if (error != null) Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: Colors.red)))),
        if (session == null) ..._overview() else ..._sessionView(),
        if (busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      ])));
  }

  List<Widget> _overview() {
    final categories = ['Alle', ...questions.map((q) => q['category'].toString()).toSet().toList()..sort()];
    return [
      const Text('Teste dein Feuerwehrwissen', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Wähle ein Thema und starte einen Test mit bis zu 10 zufälligen Fragen.'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: categories.contains(category) ? category : 'Alle',
        decoration: const InputDecoration(labelText: 'Thema'), items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
        onChanged: (v) => setState(() => category = v ?? 'Alle')),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(initialValue: difficulty, decoration: const InputDecoration(labelText: 'Schwierigkeit'),
        items: ['Alle','leicht','mittel','schwer'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
        onChanged: (v) => setState(() => difficulty = v ?? 'Alle')),
      const SizedBox(height: 12),
      Text('${filtered.length} verfügbare Fragen'),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: busy ? null : () => _start('solo'), icon: const Icon(Icons.quiz_outlined), label: const Text('Einzeltest starten')),
      OutlinedButton.icon(onPressed: busy ? null : _join, icon: const Icon(Icons.group_add_outlined), label: const Text('Gruppentest mit Code beitreten')),
      if (trainer) ...[
        const Divider(height: 35),
        const Text('Ausbilderbereich', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: busy ? null : () => _start('group'), icon: const Icon(Icons.groups), label: const Text('Gemeinsamen Test erstellen')),
        OutlinedButton.icon(onPressed: busy ? null : () => _editQuestion(), icon: const Icon(Icons.add), label: const Text('Neue Frage erstellen')),
        const SizedBox(height: 12),
        for (final q in questions) Card(child: ListTile(
          title: Text(q['question'].toString()),
          subtitle: Text('${q['category']} · ${q['difficulty']}${q['active'] == false ? ' · deaktiviert' : ''}'),
          trailing: PopupMenuButton<String>(onSelected: (v) {
            if (v == 'edit') { _editQuestion(q); }
            else { _run(() async { await db.from('fw_quiz_questions').update({'active': q['active'] != true}).eq('id', q['id']); await _load(); }); }
          }, itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
            PopupMenuItem(value: 'toggle', child: Text(q['active'] == true ? 'Deaktivieren' : 'Aktivieren'))]),
        )),
      ],
    ];
  }

  List<Widget> _sessionView() {
    final s = session!;
    final isOwner = s['created_by'] == db.auth.currentUser!.id;
    final ids = s['question_ids'] as List;
    if (s['status'] == 'waiting') return [
      const Text('Gruppentest wartet auf den Start', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      SelectableText('Teilnahmecode: ${s['code']}', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const Text('Teilnehmer geben diesen Code unter „Gruppentest beitreten“ ein.'),
      if (isOwner) FilledButton(onPressed: busy ? null : _advance, child: const Text('Test für alle starten')),
      const Text('Der Test aktualisiert sich automatisch.'),
    ];
    if (s['status'] == 'finished') return [
      const Icon(Icons.emoji_events_outlined, size: 65, color: red),
      const Text('Test abgeschlossen', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      FilledButton(onPressed: _results, child: const Text('Ergebnisse ansehen')),
    ];
    final q = currentQuestion;
    if (q == null) return [const Text('Frage wird geladen …')];
    final options = (q['options'] as List).map((e) => '$e').toList();
    return [
      if (s['mode'] == 'group') Text('Gruppencode: ${s['code']}', style: const TextStyle(fontWeight: FontWeight.bold)),
      Text('Frage ${(s['current_index'] as int) + 1} von ${ids.length}', style: const TextStyle(color: red)),
      const SizedBox(height: 12),
      Text(q['question'].toString(), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 18),
      for (var i = 0; i < options.length; i++) Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton(
        onPressed: busy || chosen != null ? null : () => _answer(i),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(15), alignment: Alignment.centerLeft,
          backgroundColor: chosen == i ? (correct == true ? Colors.green.shade100 : Colors.red.shade100) : null),
        child: Text('${String.fromCharCode(65 + i)}. ${options[i]}'),
      )),
      if (chosen != null) ...[
        Text(correct == true ? 'Richtig!' : 'Leider falsch.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: correct == true ? Colors.green : red)),
        if ((q['explanation'] ?? '').toString().isNotEmpty) Text(q['explanation'].toString()),
      ],
      const SizedBox(height: 12),
      if (s['mode'] == 'solo' && chosen != null) FilledButton(onPressed: busy ? null : _advance,
        child: Text((s['current_index'] as int) + 1 == ids.length ? 'Test beenden' : 'Nächste Frage')),
      if (s['mode'] == 'group' && isOwner) FilledButton(onPressed: busy ? null : _advance,
        child: Text((s['current_index'] as int) + 1 == ids.length ? 'Gruppentest beenden' : 'Nächste Frage für alle')),
      if (s['mode'] == 'group' && !isOwner) const Text('Der Ausbilder schaltet die nächste Frage frei.'),
      if (s['mode'] == 'group') TextButton(onPressed: _results, child: const Text('Bisherige Ergebnisse')),
    ];
  }
}
