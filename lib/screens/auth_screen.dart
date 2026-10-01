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
  static const _navy = Color(0xFF0A1F44);
  static const _blue = Color(0xFF0B4EA2);

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
          'Registrierung erfolgreich. Nach einer eventuell erforderlichen '
          'E-Mail-Bestätigung muss dein Konto noch von mindestens einem '
          'Ausbilder freigegeben werden.',
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
        'Anmeldung derzeit nicht möglich. Bitte später erneut versuchen.',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _friendlyAuthMessage(String message) {
    final lower = message.toLowerCase();

    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid credentials') ||
        lower.contains('email or password')) {
      return 'E-Mail-Adresse oder Passwort ist falsch.';
    }

    if (lower.contains('email not confirmed')) {
      return 'Bitte bestätige zuerst deine E-Mail-Adresse.';
    }

    if (lower.contains('user already registered')) {
      return 'Für diese E-Mail-Adresse besteht bereits ein Konto.';
    }

    if (_registerMode &&
        (lower.contains('password') ||
            lower.contains('weak') ||
            lower.contains('characters'))) {
      return 'Das Passwort erfüllt die Anforderungen nicht.';
    }

    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('failed to fetch') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup')) {
      return 'Keine Internetverbindung. '
          'Für eine neue Anmeldung wird eine Internetverbindung benötigt. '
          'Bitte verbinde das Gerät mit dem Internet und versuche es erneut.';
    }

    return 'Anmeldung fehlgeschlagen: $message';
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
        'Wenn für diese E-Mail-Adresse ein Konto besteht, wurde eine '
        'E-Mail zum Zurücksetzen des Passworts versendet.',
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

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.96),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFFD8E2EE),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: _blue,
          width: 2,
        ),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/branding/app_background.jpg',
            fit: BoxFit.cover,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _navy.withValues(alpha: 0.28),
                  _navy.withValues(alpha: 0.58),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Card(
                    elevation: 18,
                    shadowColor: Colors.black.withValues(alpha: 0.28),
                    color: Colors.white.withValues(alpha: 0.94),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                      child: AutofillGroup(
                        child: Column(
                          children: [
                            Container(
                              width: 112,
                              height: 112,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _navy,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: _blue.withValues(alpha: 0.35),
                                    blurRadius: 22,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: Image.asset(
                                  'assets/branding/logo.png',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Jugendfeuerwehr\nSeehausen/Kyffhäuser',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                                color: _navy,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 7),
                            const Text(
                              'Gemeinsam. Stark. Für morgen.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF475467),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 28),
                            if (_registerMode) ...[
                              TextField(
                                controller: _firstNameController,
                                textCapitalization: TextCapitalization.words,
                                autofillHints: const [
                                  AutofillHints.givenName,
                                ],
                                decoration: _inputDecoration(
                                  label: 'Vorname',
                                  icon: Icons.person_outline,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _lastNameController,
                                textCapitalization: TextCapitalization.words,
                                autofillHints: const [
                                  AutofillHints.familyName,
                                ],
                                decoration: _inputDecoration(
                                  label: 'Nachname',
                                  icon: Icons.person_outline,
                                ),
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                initialValue: _registerRole,
                                decoration: _inputDecoration(
                                  label: 'Konto für',
                                  icon: Icons.badge_outlined,
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
                                          setState(
                                            () => _registerRole = value,
                                          );
                                        }
                                      },
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              autofillHints: const [
                                AutofillHints.email,
                              ],
                              decoration: _inputDecoration(
                                label: 'E-Mail-Adresse',
                                icon: Icons.email_outlined,
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
                              decoration: _inputDecoration(
                                label: 'Passwort',
                                icon: Icons.lock_outline,
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(
                                      () => _showPassword = !_showPassword,
                                    );
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
                                  onPressed:
                                      _loading ? null : _resetPassword,
                                  child: const Text(
                                    'Passwort vergessen?',
                                  ),
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
                              height: 54,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _blue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
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
                                  'Ausbilder-Konten werden nicht selbst '
                                  'registriert, sondern durch einen '
                                  'berechtigten Ausbilder vergeben.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF667085),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: () => _openLegal(
                                    LegalSection.datenschutz,
                                  ),
                                  child: const Text('Datenschutz'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _openLegal(LegalSection.kontakt),
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
        ],
      ),
    );
  }
}
