import 'dart:async';
import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/terms_screen.dart';
import 'services/appsync_client.dart';
import 'services/auth_service.dart';
import 'services/biometric_lock.dart';
import 'services/command_service.dart';
import 'services/demo_mode.dart';
import 'services/prefs.dart';
import 'services/shortcuts_service.dart';
import 'services/update_service.dart';
import 'services/update_state.dart';
import 'services/errors.dart';
import 'services/notification_service.dart';
import 'theme.dart';

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

class _ScobySenseAppState extends State<ScobySenseApp> with WidgetsBindingObserver {
  final _auth = AuthService();
  final _updater = UpdateService();
  Timer? _updateTimer;
  bool _checking = false;
  DateTime? _lastBackground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _silentUpdateCheck());
    _updateTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _silentUpdateCheck(),
    );
    // Wire notification action handler. The handler needs auth-authenticated
    // network access so it talks through CommandService/AppSyncClient.
    NotificationService.instance.setActionHandler(_handleNotificationAction);
    // Register home-screen shortcuts and route taps into the right screen.
    ShortcutsService.instance.initialize(_handleShortcut);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _updater.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _lastBackground = DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      _silentUpdateCheck();
      _maybeBiometricLock();
    }
  }

  Future<void> _maybeBiometricLock() async {
    // Only gate when the user has actually opted in AND we were in the
    // background long enough to matter (10s avoids the lock blinking on
    // every system permission sheet).
    final last = _lastBackground;
    _lastBackground = null;
    if (last == null) return;
    if (DateTime.now().difference(last).inSeconds < 10) return;
    if (!await AppPrefs.biometricLock()) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await BiometricLock.instance.gate(ctx);
  }

  Future<String> _handleNotificationAction(
      String deviceId, String side, String action) async {
    final tokens = await _auth.currentTokens();
    if (tokens == null) {
      return 'Sign in to run notification actions.';
    }
    if (DemoMode.active) {
      return 'Demo mode — action not sent.';
    }
    final cmd = CommandService(AppSyncClient(_auth));
    switch (action) {
      case 'stop':
        await cmd.stopBrew(deviceId, side);
        return 'Turned off $side on $deviceId.';
      case 'add_day':
        final current = await AppPrefs.brewSeconds(deviceId, side);
        final next = current + 86400;
        await cmd.setBrewTimerSeconds(deviceId, side, next);
        await AppPrefs.setBrewSeconds(deviceId, side, next);
        return 'Extended $side by 1 day.';
      default:
        return 'Unknown action: $action';
    }
  }

  void _handleShortcut(String type) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    switch (type) {
      case 'live':
        // Devices screen is the live-brew entry point once signed in.
        _goToDevices(ctx);
        break;
      case 'recipes':
        _goToDevices(ctx, openRecipes: true);
        break;
      case 'demo':
        DemoMode.active = true;
        _goToDevices(ctx);
        break;
    }
  }

  Future<void> _goToDevices(BuildContext ctx,
      {bool openRecipes = false}) async {
    final signedIn =
        (await _auth.currentTokens()) != null || DemoMode.active;
    if (!ctx.mounted) return;
    if (!signedIn) {
      Navigator.of(ctx).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => LoginScreen(auth: _auth, updater: _updater)),
        (_) => false,
      );
      return;
    }
    Navigator.of(ctx).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => DevicesScreen(
          auth: _auth,
          updater: _updater,
          openRecipesOnLaunch: openRecipes,
        ),
      ),
      (_) => false,
    );
  }

  Future<void> _silentUpdateCheck() async {
    if (_checking) return;
    // Demo mode is a no-account preview; it should not phone home for releases.
    if (DemoMode.active) return;
    _checking = true;
    try {
      final info = await _updater.packageInfo();
      UpdateState.version.value = info.version;
      final release = await _updater.checkForUpdate();
      UpdateState.available.value = release;
    } on AppFailure {
      // Silent; Settings has an explicit button that surfaces errors.
    } catch (_) {
      // Same.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
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
    final onboarded = await AppPrefs.onboarded();
    return _BootStatus(
      termsOk: termsOk,
      signedIn: t != null,
      onboarded: onboarded,
    );
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
              final Widget next;
              if (status.signedIn) {
                next = DevicesScreen(
                    auth: widget.auth, updater: widget.updater);
              } else if (!status.onboarded) {
                next = OnboardingScreen(
                    auth: widget.auth, updater: widget.updater);
              } else {
                next = LoginScreen(
                    auth: widget.auth, updater: widget.updater);
              }
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
  final bool onboarded;
  const _BootStatus({
    this.termsOk = false,
    this.signedIn = false,
    this.onboarded = false,
  });
}
