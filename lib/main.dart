import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'services/developer_error_logger.dart';
import 'services/push_service.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');

const supabasePublishableKey =
    String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );

    DeveloperErrorLogger.installGlobalHandlers();

    try {
      await PushService.initialize();
    } catch (error, stack) {
      await DeveloperErrorLogger.logError(
        error,
        stack,
        source: 'PushService.initialize',
        severity: 'error',
      );
      rethrow;
    }
  }

  runApp(const JfApp());
}

class JfApp extends StatelessWidget {
  const JfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jugendfeuerwehr Seehausen/Kyffhäuser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE30613),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F5F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF102638),
          foregroundColor: Colors.white,
        ),
      ),
      home: _entry(),
    );
  }

  Widget _entry() {
    if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
      return const AuthScreen(
        configMissing: true,
      );
    }

    return const AuthGate();
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (_, snapshot) {
        if (client.auth.currentSession == null) {
          return const AuthScreen();
        }

        return const ApprovalGate();
      },
    );
  }
}

class ApprovalGate extends StatefulWidget {
  const ApprovalGate({super.key});

  @override
  State<ApprovalGate> createState() => _ApprovalGateState();
}

class _ApprovalGateState extends State<ApprovalGate> {
  final _supabase = Supabase.instance.client;
  Timer? _timer;
  bool _loading = true;
  bool _approved = false;
  String _status = 'pending';
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkApproval();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkApproval(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkApproval({bool silent = false}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final profile = await _supabase
          .from('profiles')
          .select('approval_status')
          .eq('id', user.id)
          .maybeSingle();

      final status = profile?['approval_status']?.toString() ?? 'pending';

      if (!mounted) return;
      setState(() {
        _status = status;
        _approved = status == 'approved';
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_approved) return const HomeShell();

    final rejected = _status == 'rejected';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        rejected
                            ? Icons.block_outlined
                            : Icons.hourglass_top_outlined,
                        size: 68,
                        color: rejected
                            ? const Color(0xFFE30613)
                            : const Color(0xFFFF8A00),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        rejected
                            ? 'Zugang nicht freigegeben'
                            : 'Freigabe durch Ausbilder erforderlich',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF0A1F44),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        rejected
                            ? 'Dieses Konto wurde nicht für die Jugendfeuerwehr-App freigegeben.'
                            : 'Dein Konto wurde erstellt. Mindestens ein Ausbilder muss es freigeben, bevor du die App nutzen kannst.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          height: 1.4,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFB42318),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (!rejected)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _checkApproval(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Freigabe prüfen'),
                          ),
                        ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => _supabase.auth.signOut(),
                        icon: const Icon(Icons.logout),
                        label: const Text('Abmelden'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
