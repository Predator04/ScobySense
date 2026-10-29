import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/appsync_client.dart';
import '../services/errors.dart';
import '../services/update_service.dart';
import '../models/device.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import 'device_screen.dart';
import 'recipes_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

class DevicesScreen extends StatefulWidget {
  final AuthService auth;
  final UpdateService updater;
  const DevicesScreen({super.key, required this.auth, required this.updater});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final AppSyncClient _client = AppSyncClient(widget.auth);
  Future<List<BrewerDevice>>? _future;
  bool _offline = false;
  late final StreamSubscription<List<ConnectivityResult>> _connSub;

  @override
  void initState() {
    super.initState();
    _future = _client.listDevices();
    _connSub =
        Connectivity().onConnectivityChanged.listen(_handleConnectivity);
    Connectivity().checkConnectivity().then(_handleConnectivity);
  }

  @override
  void dispose() {
    _connSub.cancel();
    super.dispose();
  }

  void _handleConnectivity(List<ConnectivityResult> result) {
    final offline = result.isEmpty ||
        result.every((r) => r == ConnectivityResult.none);
    if (offline != _offline && mounted) {
      setState(() => _offline = offline);
      if (!offline) _refresh();
    }
  }

  Future<void> _refresh() async {
    final f = _client.listDevices();
    setState(() => _future = f);
    try {
      await f;
    } on AppFailure catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(e.toString());
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'Retry', onPressed: _refresh),
      ),
    );
  }

  Future<void> _logout() async {
    await widget.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) =>
          LoginScreen(auth: widget.auth, updater: widget.updater),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Devices',
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.menu_book_outlined),
                      tooltip: 'Recipes',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RecipesScreen()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => SettingsScreen(
                                  onLogout: _logout,
                                  updater: widget.updater,
                                )),
                      ),
                    ),
                  ],
                ),
              ),
              if (_offline)
                const OfflineBanner(
                    message: 'Offline — showing last known state.'),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  color: AppTheme.accent,
                  child: FutureBuilder<List<BrewerDevice>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.accent));
                      }
                      if (snap.hasError) {
                        final err = snap.error;
                        final msg = err is AppFailure
                            ? err.message
                            : err.toString();
                        return ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            InlineErrorCard(
                                message: msg, onRetry: _refresh),
                          ],
                        );
                      }
                      final devices = snap.data ?? [];
                      if (devices.isEmpty) {
                        return ListView(
                          padding: const EdgeInsets.all(20),
                          children: const [
                            GlassCard(
                              child: Text(
                                  'No devices on this account. Pair a Fermenstation in the official ScobySense app first.',
                                  style: TextStyle(color: AppTheme.textDim)),
                            )
                          ],
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: devices.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 14),
                        itemBuilder: (_, i) => _DeviceTile(
                          device: devices[i],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DeviceScreen(
                                auth: widget.auth,
                                initial: devices[i],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final BrewerDevice device;
  final VoidCallback onTap;
  const _DeviceTile({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final online = (device.status ?? '').toLowerCase() == 'online';
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: online
                    ? const [AppTheme.accent, Color(0xFF2DD4BF)]
                    : [
                        AppTheme.textDim.withValues(alpha: 0.4),
                        AppTheme.textDim.withValues(alpha: 0.2)
                      ],
              ),
              boxShadow: online
                  ? [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.4),
                        blurRadius: 14,
                        spreadRadius: -2,
                      )
                    ]
                  : null,
            ),
            child: Icon(
              online ? Icons.local_fire_department : Icons.power_settings_new,
              color: online
                  ? const Color(0xFF04070A)
                  : AppTheme.textDim,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.deviceName ?? device.deviceId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(device.deviceId,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textDim)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Chip(
                        label: 'F1 ${device.f1On ? "ON" : "OFF"}',
                        on: device.f1On),
                    const SizedBox(width: 8),
                    _Chip(
                        label: 'F2 ${device.f2On ? "ON" : "OFF"}',
                        on: device.f2On),
                    const SizedBox(width: 8),
                    _Chip(label: online ? 'online' : 'offline', on: online),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppTheme.textDim),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  const _Chip({required this.label, required this.on});

  @override
  Widget build(BuildContext context) {
    final c = on ? AppTheme.accent : AppTheme.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: c, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
