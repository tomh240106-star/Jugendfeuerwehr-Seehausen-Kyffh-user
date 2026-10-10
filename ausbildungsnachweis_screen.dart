import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/developer_error_logger.dart';
import '../services/network_retry_service.dart';
import 'training_attendance_screen.dart';

/// Eigenständiger Ausbildungsnachweis für freigegebene Ausbilder.
class AusbildungsnachweisScreen extends StatefulWidget {
  const AusbildungsnachweisScreen({super.key});

  @override
  State<AusbildungsnachweisScreen> createState() =>
      _AusbildungsnachweisScreenState();
}

class _AusbildungsnachweisScreenState extends State<AusbildungsnachweisScreen> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  bool _allowed = false;
  String? _error;
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? _date(Map<String, dynamic> plan) {
    final raw = plan['training_date']?.toString();
    if (raw != null) {
      final date = DateTime.tryParse(raw);
      if (date != null) return date;
    }
    return DateTime.tryParse(plan['starts_at']?.toString() ?? '')?.toLocal();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw StateError('Nicht angemeldet');
      final profile = await NetworkRetryService.read(
        () => _client.from('profiles')
            .select('role,approval_status')
            .eq('id', user.id)
            .maybeSingle(),
      );
      final allowed = profile?['role'] == 'ausbilder' &&
          profile?['approval_status'] == 'approved';
      if (!allowed) {
        if (!mounted) return;
        setState(() {
          _allowed = false;
          _plans = [];
          _loading = false;
        });
        return;
      }
      final rows = await NetworkRetryService.read(
        () => _client.from('training_plans')
            .select('id,title,topic,training_date,starts_at,start_time,end_time,location'),
      );
      final plans = List<Map<String, dynamic>>.from(rows);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      plans.sort((a, b) {
        final da = _date(a);
        final db = _date(b);
        if (da == null) return db == null ? 0 : 1;
        if (db == null) return -1;
        final fa = !DateTime(da.year, da.month, da.day).isBefore(today);
        final fb = !DateTime(db.year, db.month, db.day).isBefore(today);
        if (fa != fb) return fa ? -1 : 1;
        return fa ? da.compareTo(db) : db.compareTo(da);
      });
      if (!mounted) return;
      setState(() {
        _allowed = true;
        _plans = plans;
        _loading = false;
      });
    } catch (error, stack) {
      unawaited(DeveloperErrorLogger.logNetworkError(
        error, stack,
        source: 'AusbildungsnachweisScreen._load',
        context: const {'operation': 'load_training_plans'},
      ));
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Ausbildungen konnten nicht geladen werden. Bitte erneut versuchen.';
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Kein Datum';
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d.$m.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06111F),
      appBar: AppBar(
        title: const Text('Ausbildungsnachweis'),
        backgroundColor: const Color(0xFF0A1F44),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_allowed
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nur für freigegebene Ausbilder.',
                      style: TextStyle(color: Colors.white)),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Nächste Ausbildungen zuerst. Vergangene Termine stehen darunter.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.redAccent)),
                        ),
                      if (_plans.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Keine Ausbildungen vorhanden.',
                              style: TextStyle(color: Colors.white70)),
                        ),
                      for (final plan in _plans)
                        Builder(builder: (context) {
                          final date = _date(plan);
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final day = date == null ? null :
                              DateTime(date.year, date.month, date.day);
                          final isToday = day == today;
                          final past = day != null && day.isBefore(today);
                          final title = (plan['title']?.toString().trim().isNotEmpty ?? false)
                              ? plan['title'].toString()
                              : (plan['topic']?.toString() ?? 'Ausbildung');
                          return Card(
                            color: isToday
                                ? const Color(0xFF183F35)
                                : const Color(0xFF10263A),
                            margin: const EdgeInsets.only(top: 12),
                            child: ListTile(
                              leading: Icon(
                                isToday ? Icons.today : Icons.event_note,
                                color: isToday
                                    ? Colors.lightGreenAccent
                                    : Colors.white70,
                              ),
                              title: Text(title,
                                  style: const TextStyle(color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                '${_formatDate(date)}'
                                '${isToday ? ' · Heute' : past ? ' · Vergangen' : ''}'
                                '${plan['start_time'] == null ? '' : ' · ${plan['start_time'].toString().substring(0, 5)} Uhr'}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              trailing: const Icon(Icons.chevron_right,
                                  color: Colors.white),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TrainingAttendanceScreen(
                                      plan: plan,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}
