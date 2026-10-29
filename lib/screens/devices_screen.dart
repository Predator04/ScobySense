import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/appsync_client.dart';
import '../services/errors.dart';
import '../services/prefs.dart';
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
  Future<List<KombuDevice>>? _future;
  bool _offline = false;
  Map<String, String> _localNames = const {};
  late final StreamSubscription<List<ConnectivityResult>> _connSub;

  @override
  void initState() {
    super.initState();
    _future = _client.listDevices();
    _loadLocalNames();
    _connSub =
        Connectivity().onConnectivityChanged.listen(_handleConnectivity);
    Connectivity().checkConnectivity().then(_handleConnectivity);
  }

  Future<void> _loadLocalNames() async {
    final names = await AppPrefs.loadDeviceDisplayNames();
    if (mounted) setState(() => _localNames = names);
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
    _loadLocalNames();
    try {
      await f;
    } on KombuFailure catch (e) {
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

  Future<void> _showAddDeviceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KombuTheme.bg2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: KombuTheme.accent.withValues(alpha: 0.14),
                    border: Border.all(
                        color: KombuTheme.accent.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.add_link,
                      color: KombuTheme.accent, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Add another machine',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'To add another Fermenstation, pair it in the official KOMBU app '
              'first (Bluetooth + WiFi setup). Once it is linked to your '
              'account, it will appear here automatically.',
              style: TextStyle(color: KombuTheme.text, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'ScobySense supports multiple devices — every linked machine '
              'shows as its own card on this screen.',
              style: TextStyle(color: KombuTheme.textDim, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _refresh();
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close',
                      style: TextStyle(color: KombuTheme.textDim)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDeviceSheet,
        backgroundColor: KombuTheme.accent,
        foregroundColor: const Color(0xFF04070A),
        icon: const Icon(Icons.add),
        label: const Text('Add device',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: KombuBackground(
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
                  color: KombuTheme.accent,
                  child: FutureBuilder<List<KombuDevice>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: KombuTheme.accent));
                      }
                      if (snap.hasError) {
                        final err = snap.error;
                        final msg = err is KombuFailure
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
                                  'No devices on this account. Pair a Fermenstation in the official Kombu app first.',
                                  style: TextStyle(color: KombuTheme.textDim)),
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
                          displayName:
                              _localNames[devices[i].deviceId],
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DeviceScreen(
                                  auth: widget.auth,
                                  updater: widget.updater,
                                  initial: devices[i],
                                ),
                              ),
                            );
                            _loadLocalNames();
                          },
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
  final KombuDevice device;
  final String? displayName;
  final VoidCallback onTap;
  const _DeviceTile(
      {required this.device, this.displayName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final online = (device.status ?? '').toLowerCase() == 'online';
    final name = (displayName != null && displayName!.isNotEmpty)
        ? displayName!
        : (device.deviceName ?? device.deviceId);
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
                    ? const [KombuTheme.accent, Color(0xFF2DD4BF)]
                    : [
                        KombuTheme.textDim.withValues(alpha: 0.4),
                        KombuTheme.textDim.withValues(alpha: 0.2)
                      ],
              ),
              boxShadow: online
                  ? [
                      BoxShadow(
                        color: KombuTheme.accent.withValues(alpha: 0.4),
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
                  : KombuTheme.textDim,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(device.deviceId,
                    style: const TextStyle(
                        fontSize: 11, color: KombuTheme.textDim)),
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
          const Icon(Icons.chevron_right, color: KombuTheme.textDim),
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
    final c = on ? KombuTheme.accent : KombuTheme.textDim;
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
