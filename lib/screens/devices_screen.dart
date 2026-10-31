import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/appsync_client.dart';
import '../services/demo_data.dart';
import '../services/demo_mode.dart';
import '../services/errors.dart';
import '../services/prefs.dart';
import '../services/state_cache.dart';
import '../services/update_service.dart';
import '../services/widget_service.dart';
import '../services/update_state.dart';
import '../models/device.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/update_dialog.dart';
import 'device_screen.dart';
import 'recipes_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

class DevicesScreen extends StatefulWidget {
  final AuthService auth;
  final UpdateService updater;
  final bool openRecipesOnLaunch;
  const DevicesScreen({
    super.key,
    required this.auth,
    required this.updater,
    this.openRecipesOnLaunch = false,
  });

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final AppSyncClient _client = AppSyncClient(widget.auth);
  List<BrewerDevice>? _devices;
  Object? _loadError;
  bool _loading = true;
  bool _offline = false;
  bool _fromCache = false;
  DateTime? _cacheSavedAt;
  Map<String, String> _localNames = const {};
  late final StreamSubscription<List<ConnectivityResult>> _connSub;
  bool _updateBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _loadLocalNames();
    _connSub =
        Connectivity().onConnectivityChanged.listen(_handleConnectivity);
    Connectivity().checkConnectivity().then(_handleConnectivity);
    if (widget.openRecipesOnLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RecipesScreen()),
        );
      });
    }
  }

  Future<void> _bootstrap() async {
    // Paint cache first (if any) so the screen is never blank. Then kick a
    // real load — if that succeeds, we overwrite with fresh data; if it fails,
    // we stay on the cached snapshot with a stale badge.
    if (!DemoMode.active) {
      final cached = await StateCache.instance.loadDevices();
      if (!mounted) return;
      if (cached != null && cached.devices.isNotEmpty) {
        setState(() {
          _devices = cached.devices;
          _cacheSavedAt = cached.savedAt;
          _fromCache = true;
          _loading = false;
        });
      }
    }
    await _refresh();
  }

  Future<List<BrewerDevice>> _loadDevices() {
    if (DemoMode.active) {
      return Future.value(DemoData.listDevices());
    }
    return _client.listDevices();
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
    if (mounted) {
      setState(() {
        if (_devices == null) _loading = true;
        _loadError = null;
      });
    }
    _loadLocalNames();
    try {
      final list = await _loadDevices();
      if (!mounted) return;
      setState(() {
        _devices = list;
        _loading = false;
        _fromCache = false;
        _cacheSavedAt = null;
      });
      if (!DemoMode.active) {
        await StateCache.instance.saveDevices(list);
      }
      // Keep the home-screen widget in sync even when the user never opens the
      // per-device screen. Prefer a device that's actively brewing so the
      // widget surfaces the thing someone would want to glance at.
      if (list.isNotEmpty) {
        final primary =
            list.firstWhere((d) => d.f1On || d.f2On, orElse: () => list.first);
        await WidgetService.instance.publish(primary);
      }
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
      if (_devices == null) {
        // Only snack if we have nothing to show.
      } else {
        _snack(e.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
      if (_devices != null) _snack(e.toString());
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
    DemoMode.active = false;
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
      backgroundColor: AppTheme.bg2,
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
                    color: AppTheme.accent.withValues(alpha: 0.14),
                    border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.add_link,
                      color: AppTheme.accent, size: 18),
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
              'To add another device, pair it in the official app '
              'first (Bluetooth + WiFi setup). Once it is linked to your '
              'account, it will appear here automatically.',
              style: TextStyle(color: AppTheme.text, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'ScobySense supports multiple devices — every linked machine '
              'shows as its own card on this screen.',
              style: TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openOfficialApp,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Open official app in Play Store'),
              ),
            ),
            const SizedBox(height: 16),
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
                      style: TextStyle(color: AppTheme.textDim)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOfficialApp() async {
    final url =
        Uri.parse('https://play.google.com/store/apps/details?id=com.kombu');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        await launchUrl(Uri.parse('market://details?id=com.kombu'),
            mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Ignore — user can find it manually.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDeviceSheet,
        backgroundColor: AppTheme.accent,
        foregroundColor: const Color(0xFF04070A),
        icon: const Icon(Icons.add),
        label: const Text('Add device',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
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
                    if (DemoMode.active) const _DemoBadge(),
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RecipesScreen()),
                      ),
                      icon: const Icon(Icons.menu_book_outlined, size: 20),
                      label: const Text('Recipes'),
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
              _updateBanner(),
              if (_offline)
                const OfflineBanner(
                    message: 'Offline — showing last known state.'),
              if (_fromCache && !_offline)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: StaleBadge(
                        label: formatStaleness(_cacheSavedAt)),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  color: AppTheme.accent,
                  child: _buildBody(),
                ),
              ),
              _versionFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _devices == null) {
      return ListSkeleton(
        count: 3,
        tileBuilder: (_) => const DeviceTileSkeleton(),
      );
    }
    final err = _loadError;
    if (err != null && _devices == null) {
      final msg = err is AppFailure ? err.message : err.toString();
      return ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          InlineErrorCard(
              message: msg,
              title: 'Device unreachable',
              onRetry: _refresh),
        ],
      );
    }
    final devices = _devices ?? const <BrewerDevice>[];
    if (devices.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyStateCard(
            icon: Icons.devices_other,
            title: 'No devices yet',
            body:
                'Pair a Fermenstation in the official app (Bluetooth + WiFi setup). Once it is linked to your account, it will appear here automatically.',
            actionLabel: 'Refresh',
            onAction: _refresh,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) => _DeviceTile(
        device: devices[i],
        displayName: _localNames[devices[i].deviceId],
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
  }

  Widget _updateBanner() {
    return ValueListenableBuilder<ReleaseInfo?>(
      valueListenable: UpdateState.available,
      builder: (context, release, _) {
        if (release == null || _updateBannerDismissed) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                final current = UpdateState.version.value;
                showUpdateFlow(
                  context,
                  widget.updater,
                  release,
                  currentVersion: current.isEmpty ? release.tag : current,
                );
              },
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: AppTheme.accent.withValues(alpha: 0.14),
                      border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.system_update_alt,
                        color: AppTheme.accent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update available — v${release.version}',
                          style: const TextStyle(
                              color: AppTheme.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'tap to download',
                          style: TextStyle(
                              color: AppTheme.textDim, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close,
                        color: AppTheme.textDim, size: 18),
                    onPressed: () =>
                        setState(() => _updateBannerDismissed = true),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _versionFooter() {
    return ValueListenableBuilder<String>(
      valueListenable: UpdateState.version,
      builder: (context, version, _) {
        if (version.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Center(
            child: Text(
              'v$version',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textDim.withValues(alpha: 0.6),
                letterSpacing: 0.3,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final BrewerDevice device;
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
                Text(name,
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

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent2.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.accent2.withValues(alpha: 0.5)),
      ),
      child: const Text(
        'DEMO',
        style: TextStyle(
          color: AppTheme.accent2,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
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
