import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  final bool configMissing;

  const AuthScreen({
    super.key,
    this.configMissing = false,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _registerMode = false;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _message = 'Bitte E-Mail-Adresse und Passwort eingeben.';
      });
      return;
    }

    if (password.length < 6) {
      setState(() {
        _message = 'Das Passwort muss mindestens 6 Zeichen lang sein.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final supabase = Supabase.instance.client;

      if (_registerMode) {
        await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'role': 'eltern',
          },
        );

        if (mounted) {
          setState(() {
            _message =
                'Registrierung erfolgreich. Bitte prüfe gegebenenfalls deine E-Mails.';
          });
        }
      } else {
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Fehler: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.configMissing) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Jugendfeuerwehr'),
        ),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Die Verbindung zur Datenbank fehlt.\n\n'
              'Bitte SUPABASE_URL und SUPABASE_ANON_KEY konfigurieren.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 450,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.local_fire_department,
                    size: 90,
                    color: Color(0xFFE30613),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Jugendfeuerwehr\nSeehausen/Kyffhäuser',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF102638),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Gemeinsam. Stark. Für morgen.',
                    style: TextStyle(
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'E-Mail-Adresse',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Passwort',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: 16,
                      ),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.red,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(),
                            )
                          : Text(
                              _registerMode
                                  ? 'Registrieren'
                                  : 'Anmelden',
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _registerMode = !_registerMode;
                              _message = null;
                            });
                          },
                    child: Text(
                      _registerMode
                          ? 'Bereits registriert? Anmelden'
                          : 'Noch kein Konto? Registrieren',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
