import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/terms_screen.dart';
import 'services/auth_service.dart';
import 'services/prefs.dart';
import 'services/update_service.dart';
import 'services/errors.dart';
import 'services/notification_service.dart';
import 'theme.dart';
import 'widgets/update_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const ScobySenseApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

class ScobySenseApp extends StatefulWidget {
  const ScobySenseApp({super.key});

  @override
  State<ScobySenseApp> createState() => _ScobySenseAppState();
}

class _ScobySenseAppState extends State<ScobySenseApp> {
  final _auth = AuthService();
  final _updater = UpdateService();
  bool _updateChecked = false;

  @override
  void dispose() {
    _updater.dispose();
    super.dispose();
  }

  Future<void> _silentUpdateCheck() async {
    if (_updateChecked) return;
    _updateChecked = true;
    try {
      final release = await _updater.checkForUpdate();
      if (release == null) return;
      final info = await _updater.packageInfo();
      final ctx = navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      await showUpdateFlow(
        ctx,
        _updater,
        release,
        currentVersion: '${info.version}+${info.buildNumber}',
      );
    } on AppFailure {
      // Silent on launch; Settings has an explicit button that surfaces errors.
    } catch (_) {
      // Same.
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _silentUpdateCheck());
    return MaterialApp(
      title: 'ScobySense',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.build(),
      home: _Boot(auth: _auth, updater: _updater),
    );
  }
}

class _Boot extends StatefulWidget {
  final AuthService auth;
  final UpdateService updater;
  const _Boot({required this.auth, required this.updater});

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  Future<_BootStatus>? _status;
  bool _handed = false;

  @override
  void initState() {
    super.initState();
    _status = _check();
  }

  Future<_BootStatus> _check() async {
    final termsOk = await AppPrefs.termsAccepted();
    final t = await widget.auth.currentTokens();
    return _BootStatus(termsOk: termsOk, signedIn: t != null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: FutureBuilder<_BootStatus>(
          future: _status,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              );
            }
            final status = snap.data ?? const _BootStatus();
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (_handed || !mounted) return;
              _handed = true;
              final ctx = context;
              if (!ctx.mounted) return;
              if (!status.termsOk) {
                final accepted = await Navigator.of(ctx).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const TermsScreen(requireAccept: true),
                    fullscreenDialog: true,
                  ),
                );
                if (accepted != true) {
                  _handed = false;
                  return;
                }
                if (!mounted || !ctx.mounted) return;
              }
              final next = status.signedIn
                  ? DevicesScreen(auth: widget.auth, updater: widget.updater)
                  : LoginScreen(auth: widget.auth, updater: widget.updater);
              Navigator.of(ctx).pushReplacement(
                MaterialPageRoute(builder: (_) => next),
              );
            });
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class _BootStatus {
  final bool termsOk;
  final bool signedIn;
  const _BootStatus({this.termsOk = false, this.signedIn = false});
}
