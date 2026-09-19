import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legal_screen.dart';

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
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  bool _loading = false;
  bool _registerMode = false;
  bool _showPassword = false;
  String _registerRole = 'jugendmitglied';
  String? _message;
  bool _messageIsError = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  void _setMessage(String message, {bool error = true}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    if (!_isValidEmail(email)) {
      _setMessage('Bitte eine gültige E-Mail-Adresse eingeben.');
      return;
    }

    if (password.length < 8) {
      _setMessage('Das Passwort muss mindestens 8 Zeichen lang sein.');
      return;
    }

    if (_registerMode && (firstName.isEmpty || lastName.isEmpty)) {
      _setMessage('Bitte Vor- und Nachname eingeben.');
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
            'first_name': firstName,
            'last_name': lastName,
            'role': _registerRole,
          },
        );

        _setMessage(
          'Registrierung erfolgreich. Bitte prüfe deine E-Mails, falls eine Bestätigung erforderlich ist.',
          error: false,
        );
      } else {
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } on AuthException catch (error) {
      _setMessage(_friendlyAuthMessage(error.message));
    } catch (_) {
      _setMessage(
          'Anmeldung derzeit nicht möglich. Bitte später erneut versuchen.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _friendlyAuthMessage(String message) {
    final lower = message.toLowerCase();

    if (lower.contains('invalid login credentials')) {
      return 'E-Mail-Adresse oder Passwort ist falsch.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Bitte bestätige zuerst deine E-Mail-Adresse.';
    }
    if (lower.contains('user already registered')) {
      return 'Für diese E-Mail-Adresse besteht bereits ein Konto.';
    }
    if (lower.contains('password')) {
      return 'Das Passwort erfüllt die Anforderungen nicht.';
    }

    return message;
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (!_isValidEmail(email)) {
      _setMessage(
        'Bitte zuerst deine E-Mail-Adresse eingeben.',
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _setMessage(
        'Wenn für diese E-Mail-Adresse ein Konto besteht, wurde eine E-Mail zum Zurücksetzen des Passworts versendet.',
        error: false,
      );
    } catch (_) {
      _setMessage(
        'Die Anfrage konnte nicht gesendet werden. Bitte später erneut versuchen.',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _openLegal(LegalSection section) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalScreen(initialSection: section),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.configMissing) {
      return const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Die Verbindung zur Datenbank fehlt.\n\n'
                'Bitte SUPABASE_URL und SUPABASE_ANON_KEY konfigurieren.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: Color(0xFFE3E8EE)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AutofillGroup(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.local_fire_department,
                          size: 82,
                          color: Color(0xFFE30613),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Jugendfeuerwehr\nSeehausen/Kyffhäuser',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0A1F44),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text('Gemeinsam. Stark. Für morgen.'),
                        const SizedBox(height: 30),
                        if (_registerMode) ...[
                          TextField(
                            controller: _firstNameController,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.givenName],
                            decoration: const InputDecoration(
                              labelText: 'Vorname',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _lastNameController,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.familyName],
                            decoration: const InputDecoration(
                              labelText: 'Nachname',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _registerRole,
                            decoration: const InputDecoration(
                              labelText: 'Konto für',
                              prefixIcon: Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'jugendmitglied',
                                child: Text('Jugendmitglied'),
                              ),
                              DropdownMenuItem(
                                value: 'eltern',
                                child: Text('Elternteil'),
                              ),
                            ],
                            onChanged: _loading
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _registerRole = value);
                                    }
                                  },
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'E-Mail-Adresse',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_showPassword,
                          autofillHints: [
                            _registerMode
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          decoration: InputDecoration(
                            labelText: 'Passwort',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() => _showPassword = !_showPassword);
                              },
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          onSubmitted: (_) {
                            if (!_loading) _submit();
                          },
                        ),
                        if (!_registerMode)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _loading ? null : _resetPassword,
                              child: const Text('Passwort vergessen?'),
                            ),
                          )
                        else
                          const SizedBox(height: 14),
                        if (_message != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _messageIsError
                                  ? const Color(0xFFFFF1F1)
                                  : const Color(0xFFEEF8F0),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _message!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _messageIsError
                                    ? const Color(0xFFB42318)
                                    : const Color(0xFF166534),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _registerMode
                                        ? 'Konto erstellen'
                                        : 'Anmelden',
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
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
                        if (_registerMode)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Ausbilder-Konten werden nicht selbst registriert, '
                              'sondern durch einen berechtigten Ausbilder vergeben.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF667085),
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  _openLegal(LegalSection.datenschutz),
                              child: const Text('Datenschutz'),
                            ),
                            TextButton(
                              onPressed: () => _openLegal(LegalSection.kontakt),
                              child: const Text('Kontakt'),
                            ),
                          ],
                        ),
                      ],
                    ),
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
