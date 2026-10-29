import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/errors.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import 'devices_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthService auth;
  final UpdateService updater;
  const LoginScreen({super.key, required this.auth, required this.updater});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.login(email, _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) =>
            DevicesScreen(auth: widget.auth, updater: widget.updater),
      ));
    } on KombuFailure catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: KombuBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: const LinearGradient(colors: [
                                KombuTheme.accent,
                                KombuTheme.accent2,
                              ]),
                              boxShadow: [
                                BoxShadow(
                                  color: KombuTheme.accent
                                      .withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.local_drink,
                                color: Color(0xFF04070A), size: 26),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Kombu',
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700)),
                                Text('Fermenstation client',
                                    style: TextStyle(
                                        color: KombuTheme.textDim,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _busy ? null : _login(),
                        decoration:
                            const InputDecoration(labelText: 'Password'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: KombuTheme.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    KombuTheme.danger.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: KombuTheme.danger, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!,
                                    style: const TextStyle(
                                        color: KombuTheme.danger,
                                        fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _busy ? null : _login,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF04070A)))
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Uses your Kombu (thekombu.com) account. Credentials go only to Amazon Cognito.',
                        style: TextStyle(
                            fontSize: 12, color: KombuTheme.textDim),
                        textAlign: TextAlign.center,
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
