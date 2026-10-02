import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/developer_error_logger.dart';
import '../services/network_retry_service.dart';

class UserBugReportsAdminScreen extends StatefulWidget {
  const UserBugReportsAdminScreen({super.key});
  @override
  State<UserBugReportsAdminScreen> createState() => _UserBugReportsAdminScreenState();
}

class _UserBugReportsAdminScreenState extends State<UserBugReportsAdminScreen> {
  static const _navy = Color(0xFF06111F);
  static const _blue = Color(0xFF00A8FF);
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<bool> _isDeveloper() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    return await NetworkRetryService.read(
        () => _supabase.from('developer_access').select('user_id').eq('user_id', user.id).maybeSingle() != null,
      );
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (!await _isDeveloper()) throw Exception('Kein Entwicklerzugriff.');
      final data = await NetworkRetryService.read(
        () => _supabase.from('user_bug_reports').select().order('created_at', ascending: false),
      );
      if (!mounted) return;
      setState(() { _rows = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (e, stack) {
      unawaited(
        DeveloperErrorLogger.logNetworkError(
          e,
          stack,
          source: 'UserBugReportsAdminScreen._load',
          context: const {'operation': 'load_user_bug_reports'},
        ),
      );
      if (!mounted) return;
      setState(() {
        _error =
            'Fehlermeldungen konnten derzeit nicht geladen werden. Bitte versuche es erneut.';
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    try {
      final user = _supabase.auth.currentUser;
      await _supabase.from('user_bug_reports').update({
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'handled_by': user?.id,
      }).eq('id', row['id']);
      await _load();
    } catch (e, stack) {
      unawaited(
        DeveloperErrorLogger.logNetworkError(
          e,
          stack,
          source: 'UserBugReportsAdminScreen._setStatus',
          context: const {'operation': 'update_bug_report_status'},
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Status konnte derzeit nicht geändert werden. Bitte versuche es erneut.',
          ),
        ),
      );
    }
  }

  String _label(String s) => switch (s) { 'in_progress' => 'In Bearbeitung', 'done' => 'Erledigt', _ => 'Neu' };
  Color _color(String s) => switch (s) { 'in_progress' => Colors.orange, 'done' => Colors.green, _ => const Color(0xFFE30613) };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(backgroundColor: _navy, foregroundColor: Colors.white, title: const Text('Fehlermeldungen'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _blue))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _rows.isEmpty
                      ? ListView(children: const [SizedBox(height: 180), Center(child: Text('Keine Fehlermeldungen vorhanden.', style: TextStyle(color: Colors.white70)))])
                      : ListView.builder(
                          padding: const EdgeInsets.all(14),
                          itemCount: _rows.length,
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            final status = r['status']?.toString() ?? 'new';
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ExpansionTile(
                                leading: CircleAvatar(backgroundColor: _color(status).withValues(alpha: .15), child: Icon(Icons.bug_report_outlined, color: _color(status))),
                                title: Text(r['title']?.toString() ?? 'Ohne Titel', style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text('${r['app_area'] ?? 'Sonstiges'} · ${_label(status)}'),
                                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                children: [
                                  Align(alignment: Alignment.centerLeft, child: Text(r['description']?.toString() ?? '', style: const TextStyle(height: 1.35))),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    initialValue: status,
                                    decoration: const InputDecoration(labelText: 'Status'),
                                    items: const [
                                      DropdownMenuItem(value: 'new', child: Text('Neu')),
                                      DropdownMenuItem(value: 'in_progress', child: Text('In Bearbeitung')),
                                      DropdownMenuItem(value: 'done', child: Text('Erledigt')),
                                    ],
                                    onChanged: (v) { if (v != null && v != status) _setStatus(r, v); },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
