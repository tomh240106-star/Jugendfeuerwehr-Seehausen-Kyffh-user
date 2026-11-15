
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CashierPermissionsScreen extends StatefulWidget {
  const CashierPermissionsScreen({super.key});

  @override
  State<CashierPermissionsScreen> createState() =>
      _CashierPermissionsScreenState();
}

class _CashierPermissionsScreenState
    extends State<CashierPermissionsScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _trainers = [];
  Set<String> _cashierIds = {};
  final Set<String> _savingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final allowed =
          await _supabase.rpc('is_cashier_manager');

      if (allowed != true) {
        throw Exception(
          'Nur Ausbilder dürfen Kassenwarte verwalten.',
        );
      }

      final trainers = await _supabase
          .from('profiles')
          .select('id, first_name, last_name')
          .eq('role', 'ausbilder');

      final cashiers = await _supabase
          .from('cashier_access')
          .select('user_id');

      if (!mounted) return;

      setState(() {
        _trainers = (trainers as List)
            .map((item) =>
                Map<String, dynamic>.from(item as Map))
            .toList();

        _cashierIds = (cashiers as List)
            .map((item) => item['user_id'].toString())
            .toSet();

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

  Future<void> _setCashier(
    String userId,
    bool enabled,
  ) async {
    if (_savingIds.contains(userId)) return;

    setState(() => _savingIds.add(userId));

    try {
      if (enabled) {
        await _supabase.from('cashier_access').insert({
          'user_id': userId,
        });
      } else {
        await _supabase
            .from('cashier_access')
            .delete()
            .eq('user_id', userId);
      }

      if (!mounted) return;

      setState(() {
        if (enabled) {
          _cashierIds.add(userId);
        } else {
          _cashierIds.remove(userId);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Kassenwart wurde freigeschaltet.'
                : 'Kassenwart-Berechtigung wurde entfernt.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingIds.remove(userId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kassenwarte verwalten'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_error!),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Hier können alle Ausbilder '
                        'festlegen, wer Kassenwart ist.',
                      ),
                      const SizedBox(height: 16),
                      for (final trainer in _trainers)
                        Card(
                          child: SwitchListTile(
                            secondary: const Icon(
                              Icons.account_balance_wallet,
                            ),
                            title: Text(
                              '${trainer['first_name'] ?? ''} '
                                      '${trainer['last_name'] ?? ''}'
                                  .trim(),
                            ),
                            subtitle: Text(
                              _cashierIds.contains(
                                trainer['id'].toString(),
                              )
                                  ? 'Kassenwart'
                                  : 'Ausbilder',
                            ),
                            value: _cashierIds.contains(
                              trainer['id'].toString(),
                            ),
                            onChanged: _savingIds.contains(
                              trainer['id'].toString(),
                            )
                                ? null
                                : (value) => _setCashier(
                                      trainer['id'].toString(),
                                      value,
                                    ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
