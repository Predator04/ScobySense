import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../theme.dart';

class BiometricLock {
  BiometricLock._();
  static final BiometricLock instance = BiometricLock._();

  final _auth = LocalAuthentication();
  bool _showing = false;

  Future<bool> available() async {
    try {
      final can = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return can && supported;
    } catch (_) {
      return false;
    }
  }

  /// Blocks the UI with an opaque sheet until the user authenticates.
  /// Safe to call multiple times — no-op if already showing.
  Future<void> gate(BuildContext context) async {
    if (_showing) return;
    _showing = true;
    try {
      await showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        pageBuilder: (ctx, _, __) => const _LockScreen(),
      );
    } finally {
      _showing = false;
    }
  }

  Future<bool> prompt(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen();

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await BiometricLock.instance
        .prompt('Unlock ScobySense to continue.');
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = 'Authentication failed. Tap to try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [
                    AppTheme.accent,
                    AppTheme.accent2,
                  ]),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withValues(alpha: 0.4),
                      blurRadius: 24,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: const Icon(Icons.lock, color: Color(0xFF04070A), size: 32),
              ),
              const SizedBox(height: 20),
              const Text('ScobySense is locked',
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Unlock with biometrics or your device PIN.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textDim)),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.danger)),
              ],
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _busy ? null : _authenticate,
                icon: const Icon(Icons.fingerprint),
                label: Text(_busy ? 'Waiting…' : 'Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
