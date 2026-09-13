import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'services/push_service.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    await PushService.initialize();
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
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      return const AuthScreen(configMissing: true);
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
        return const HomeShell();
      },
    );
  }
}
