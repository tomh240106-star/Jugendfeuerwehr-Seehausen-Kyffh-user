import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/developer_error_logger.dart';
import '../services/home_navigation.dart';

class DeveloperConsoleScreen extends StatefulWidget {
  const DeveloperConsoleScreen({super.key});

  @override
  State<DeveloperConsoleScreen> createState() =>
      _DeveloperConsoleScreenState();
}

class _DeveloperConsoleScreenState
    extends State<DeveloperConsoleScreen> {
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);
  static const _red = Color(0xFFE30613);
  static const _orange = Color(0xFFFF7A00);
  static const _green = Color(0xFF13A05B);

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _isDeveloper = false;
  String? _error;

  String _filter = 'open';
  String _query = '';

  List<Map<String, dynamic>> _logs = [];
  Map<String, String> _reporterNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> _checkDeveloper() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    final row = await _supabase
        .from('developer_access')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    return row != null;
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final developer = await _checkDeveloper();

      if (!developer) {
        if (!mounted) return;

        setState(() {
          _isDeveloper = false;
          _loading = false;
        });
        return;
      }

      final rows = await _supabase
          .from('app_error_logs')
          .select()
          .order('created_at', ascending: false)
          .limit(500);

      final logs = List<Map<String, dynamic>>.from(rows);
      final names = await _loadReporterNames(logs);

      if (!mounted) return;

      setState(() {
        _isDeveloper = true;
        _logs = logs;
        _reporterNames = names;
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

  Future<Map<String, String>> _loadReporterNames(
    List<Map<String, dynamic>> logs,
  ) async {
    final ids = logs
        .map((row) => row['user_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return {};

    try {
      final rows = await _supabase
          .from('profiles')
          .select('id,first_name,last_name')
          .inFilter('id', ids);

      final result = <String, String>{};

      for (final row in rows) {
        final id = row['id']?.toString();
        if (id == null) continue;

        final first =
            row['first_name']?.toString().trim() ?? '';
        final last =
            row['last_name']?.toString().trim() ?? '';
        final name = '$first $last'.trim();

        if (name.isNotEmpty) {
          result[id] = name;
        }
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  int get _openCount =>
      _logs.where((row) => row['status'] == 'open').length;

  int get _resolvedCount =>
      _logs.where((row) => row['status'] == 'resolved').length;

  int get _fatalCount =>
      _logs.where((row) => row['severity'] == 'fatal').length;

  List<Map<String, dynamic>> get _filteredLogs {
    final q = _query.trim().toLowerCase();

    return _logs.where((row) {
      final status = row['status']?.toString() ?? 'open';

      if (_filter != 'all' && status != _filter) {
        return false;
      }

      if (q.isEmpty) return true;

      final userId = row['user_id']?.toString() ?? '';
      final reporter = _reporterNames[userId] ?? '';

      final haystack = [
        row['message'],
        row['source'],
        row['platform'],
        row['severity'],
        reporter,
        userId,
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');

      return haystack.contains(q);
    }).toList();
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'fatal':
        return const Color(0xFF9B1C1C);
      case 'warning':
        return _orange;
      case 'info':
        return _blue;
      default:
        return _red;
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'fatal':
        return Icons.dangerous_outlined;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'info':
        return Icons.info_outline;
      default:
        return Icons.error_outline;
    }
  }

  String _severityLabel(String severity) {
    switch (severity) {
      case 'fatal':
        return 'Kritisch';
      case 'warning':
        return 'Warnung';
      case 'info':
        return 'Info';
      default:
        return 'Fehler';
    }
  }

  String _dateTime(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '-';

    final local = date.toLocal();

    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _reporter(Map<String, dynamic> row) {
    final userId = row['user_id']?.toString() ?? '';

    if (userId.isEmpty) return 'Unbekanntes Konto';

    final name = _reporterNames[userId];
    if (name != null && name.isNotEmpty) {
      return name;
    }

    final shortLength = userId.length < 8 ? userId.length : 8;
    return 'Benutzer ${userId.substring(0, shortLength)}';
  }

  Future<void> _setResolved(
    Map<String, dynamic> row,
    bool resolved,
  ) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase
          .from('app_error_logs')
          .update({
            'status': resolved ? 'resolved' : 'open',
            'resolved_at':
                resolved ? DateTime.now().toUtc().toIso8601String() : null,
            'resolved_by': resolved ? user.id : null,
          })
          .eq('id', row['id']);

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status konnte nicht geändert werden: $e'),
        ),
      );
    }
  }

  Future<void> _deleteLog(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fehlerprotokoll löschen?'),
        content: const Text(
          'Der Eintrag wird dauerhaft aus der Entwicklerkonsole gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: _red,
            ),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase
          .from('app_error_logs')
          .delete()
          .eq('id', row['id']);

      if (!mounted) return;

      Navigator.of(context).maybePop();
      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Löschen fehlgeschlagen: $e'),
        ),
      );
    }
  }

  String _contextText(dynamic value) {
    if (value == null) return '{}';

    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  Future<void> _copyDetails(Map<String, dynamic> row) async {
    final text = [
      'Jugendfeuerwehr Entwicklerkonsole',
      'Zeit: ${_dateTime(row['created_at'])}',
      'Status: ${row['status']}',
      'Schweregrad: ${row['severity']}',
      'Quelle: ${row['source']}',
      'Plattform: ${row['platform'] ?? '-'}',
      'Benutzer: ${_reporter(row)}',
      '',
      'Fehler:',
      row['message']?.toString() ?? '',
      '',
      'Stacktrace:',
      row['stack_trace']?.toString() ?? '',
      '',
      'Kontext:',
      _contextText(row['context']),
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fehlerdetails wurden kopiert.'),
      ),
    );
  }

  Future<void> _showDetails(Map<String, dynamic> row) async {
    final severity = row['severity']?.toString() ?? 'error';
    final resolved = row['status'] == 'resolved';

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.86,
          minChildSize: 0.55,
          maxChildSize: 0.97,
          builder: (_, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          _severityColor(severity).withValues(alpha: 0.12),
                      child: Icon(
                        _severityIcon(severity),
                        color: _severityColor(severity),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _severityLabel(severity),
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Schließen',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _DetailLine(
                  label: 'Zeit',
                  value: _dateTime(row['created_at']),
                ),
                _DetailLine(
                  label: 'Quelle',
                  value: row['source']?.toString() ?? '-',
                ),
                _DetailLine(
                  label: 'Plattform',
                  value: row['platform']?.toString() ?? '-',
                ),
                _DetailLine(
                  label: 'Benutzer',
                  value: _reporter(row),
                ),
                _DetailLine(
                  label: 'Status',
                  value: resolved ? 'Erledigt' : 'Offen',
                ),
                const SizedBox(height: 14),
                const Text(
                  'Fehlermeldung',
                  style: TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                _CodeBox(
                  text: row['message']?.toString() ?? '-',
                ),
                const SizedBox(height: 14),
                const Text(
                  'Stacktrace',
                  style: TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                _CodeBox(
                  text: row['stack_trace']?.toString().trim().isNotEmpty ==
                          true
                      ? row['stack_trace'].toString()
                      : 'Kein Stacktrace vorhanden.',
                ),
                const SizedBox(height: 14),
                const Text(
                  'Kontext',
                  style: TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                _CodeBox(
                  text: _contextText(row['context']),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _setResolved(row, !resolved);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: resolved ? _orange : _green,
                  ),
                  icon: Icon(
                    resolved
                        ? Icons.refresh
                        : Icons.check_circle_outline,
                  ),
                  label: Text(
                    resolved
                        ? 'Wieder öffnen'
                        : 'Als erledigt markieren',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _copyDetails(row),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Details kopieren'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _deleteLog(row),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Fehlerprotokoll löschen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createTestLog() async {
    await DeveloperErrorLogger.logError(
      StateError('Manueller Testeintrag der Entwicklerkonsole'),
      StackTrace.current,
      source: 'DeveloperConsole',
      severity: 'warning',
      context: {
        'purpose': 'Prüfung der Fehlerprotokollierung',
      },
    );

    await _load();
  }

  String get _platform {
    if (kIsWeb) return 'Web';
    return defaultTargetPlatform.name;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F5F7),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_isDeveloper) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F5F7),
        appBar: AppBar(
          title: const Text('Entwicklerkonsole'),
          backgroundColor: _navy,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 58,
                  color: _red,
                ),
                SizedBox(height: 14),
                Text(
                  'Kein Entwicklerzugriff',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
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
        title: const Text('Entwicklerkonsole'),
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
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
                    Icons.developer_mode_outlined,
                    color: Colors.white,
                    size: 36,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Privater Entwicklerbereich – Zugriff ausschließlich '
                      'für das freigeschaltete Entwicklerkonto',
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
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    value: '${_logs.length}',
                    label: 'Gesamt',
                    color: _blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    value: '$_openCount',
                    label: 'Offen',
                    color: _red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    value: '$_resolvedCount',
                    label: 'Erledigt',
                    color: _green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    value: '$_fatalCount',
                    label: 'Kritisch',
                    color: const Color(0xFF9B1C1C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFE3E8EE),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Systemdiagnose',
                    style: TextStyle(
                      color: _navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DiagnosticRow(
                    label: 'Entwicklerzugriff',
                    value: 'Aktiv',
                    ok: true,
                  ),
                  _DiagnosticRow(
                    label: 'Supabase-Sitzung',
                    value: _supabase.auth.currentUser == null
                        ? 'Nicht angemeldet'
                        : 'Angemeldet',
                    ok: _supabase.auth.currentUser != null,
                  ),
                  _DiagnosticRow(
                    label: 'Plattform',
                    value: _platform,
                    ok: true,
                  ),
                  _DiagnosticRow(
                    label: 'Fehlerlogging',
                    value: 'Aktiv',
                    ok: true,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _createTestLog,
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Testfehler protokollieren'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) {
                setState(() => _query = value);
              },
              decoration: InputDecoration(
                hintText: 'Fehler durchsuchen',
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
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Offen'),
                  selected: _filter == 'open',
                  onSelected: (_) {
                    setState(() => _filter = 'open');
                  },
                ),
                ChoiceChip(
                  label: const Text('Erledigt'),
                  selected: _filter == 'resolved',
                  onSelected: (_) {
                    setState(() => _filter = 'resolved');
                  },
                ),
                ChoiceChip(
                  label: const Text('Alle'),
                  selected: _filter == 'all',
                  onSelected: (_) {
                    setState(() => _filter = 'all');
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_filteredLogs.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFE3E8EE),
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 56,
                      color: _green,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Keine passenden Fehlerprotokolle.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._filteredLogs.map((row) {
                final severity =
                    row['severity']?.toString() ?? 'error';
                final resolved = row['status'] == 'resolved';
                final message =
                    row['message']?.toString() ?? 'Unbekannter Fehler';

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    leading: CircleAvatar(
                      backgroundColor:
                          _severityColor(severity).withValues(alpha: 0.12),
                      child: Icon(
                        _severityIcon(severity),
                        color: _severityColor(severity),
                      ),
                    ),
                    title: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      '${_severityLabel(severity)} · '
                      '${row['source'] ?? 'app'} · '
                      '${row['platform'] ?? '-'}\n'
                      '${_reporter(row)} · '
                      '${_dateTime(row['created_at'])}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      resolved
                          ? Icons.check_circle
                          : Icons.chevron_right,
                      color: resolved ? _green : null,
                    ),
                    onTap: () => _showDetails(row),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _SummaryCard({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: color.withValues(alpha: 0.20),
        ),
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

class _DiagnosticRow extends StatelessWidget {
  final String label;
  final String value;
  final bool ok;

  const _DiagnosticRow({
    required this.label,
    required this.value,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            size: 18,
            color: ok
                ? const Color(0xFF13A05B)
                : const Color(0xFFE30613),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF0A1F44),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0A1F44),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  final String text;

  const _CodeBox({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE3E8EE),
        ),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.35,
          color: Color(0xFF1F2937),
        ),
      ),
    );
  }
}
