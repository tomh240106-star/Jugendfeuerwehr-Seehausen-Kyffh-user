import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  final bool configMissing;
  const AuthScreen({super.key, this.configMissing = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final firstName = TextEditingController();
  final lastName = TextEditingController();

  bool loading = false;
  bool register = false;
  String role = 'jugendmitglied';
  String? message;

  Future<void> submit() async {
    setState(() {
      loading = true;
      message = null;
    });

    try {
      if (register) {
        final result = await Supabase.instance.client.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          data: {
            'first_name': firstName.text.trim(),
            'last_name': lastName.text.trim(),
            'role': role,
          },
        );

        if (result.user != null) {
          await Supabase.instance.client.from('profiles').upsert({
            'id': result.user!.id,
            'first_name': firstName.text.trim(),
            'last_name': lastName.text.trim(),
            'role': role,
          });
        }

        setState(() => message = 'Registrierung erfolgreich. Prüfe ggf. deine E-Mail.');
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on AuthException catch (e) {
      setState(() => message = e.message);
    } catch (e) {
      setState(() => message = e.toString());
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> resetPassword() async {
    if (email.text.trim().isEmpty) {
      setState(() => message = 'Bitte zuerst deine E-Mail eingeben.');
      return;
    }

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email.text.trim());
      setState(() => message = 'E-Mail zum Zurücksetzen wurde angefordert.');
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF102638), Color(0xFF07131D)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset(
                        'assets/logo.jpg',
                        width: 115,
                        height: 115,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'JUGENDFEUERWEHR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'SEEHAUSEN/KYFFHÄUSER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Gemeinsam. Stark. Für morgen.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 28),
                    if (widget.configMissing)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Backend noch nicht konfiguriert. SUPABASE_URL und SUPABASE_ANON_KEY setzen.',
                          ),
                        ),
                      ),
                    if (register) ...[
                      TextField(
                        controller: firstName,
                        decoration: const InputDecoration(
                          labelText: 'Vorname',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: lastName,
                        decoration: const InputDecoration(
                          labelText: 'Nachname',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: role,
                        decoration: const InputDecoration(
                          labelText: 'Rolle',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'jugendmitglied', child: Text('Jugendmitglied')),
                          DropdownMenuItem(value: 'eltern', child: Text('Eltern')),
                        ],
                        onChanged: (v) => setState(() => role = v ?? 'jugendmitglied'),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-Mail',
                        prefixIcon: Icon(Icons.email),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Passwort',
                        prefixIcon: Icon(Icons.lock),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          message!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: widget.configMissing || loading ? null : submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE30613),
                          padding: const EdgeInsets.all(16),
                        ),
                        child: Text(
                          loading
                              ? 'Bitte warten...'
                              : register
                                  ? 'REGISTRIEREN'
                                  : 'ANMELDEN',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => register = !register),
                      child: Text(
                        register ? 'Bereits ein Konto? Anmelden' : 'Noch kein Konto? Registrieren',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    if (!register)
                      TextButton(
                        onPressed: resetPassword,
                        child: const Text(
                          'Passwort vergessen?',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
