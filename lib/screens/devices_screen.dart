import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/appsync_client.dart';
import '../models/device.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import 'device_screen.dart';
import 'recipes_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

class DevicesScreen extends StatefulWidget {
  final AuthService auth;
  const DevicesScreen({super.key, required this.auth});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final AppSyncClient _client = AppSyncClient(widget.auth);
  Future<List<BrewerDevice>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _client.listDevices();
  }

  Future<void> _refresh() async {
    setState(() => _future = _client.listDevices());
    await _future;
  }

  Future<void> _logout() async {
    await widget.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LoginScreen(auth: widget.auth),
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
                              fontSize: 24, fontWeight: FontWeight.w700)),
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
                            builder: (_) =>
                                SettingsScreen(onLogout: _logout)),
                      ),
                    ),
                  ],
                ),
              ),
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
                        return ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            GlassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Could not load devices',
                                      style: TextStyle(
                                          color: AppTheme.danger,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  Text(snap.error.toString(),
                                      style: const TextStyle(
                                          color: AppTheme.textDim)),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                      onPressed: _refresh,
                                      child: const Text('Retry')),
                                ],
                              ),
                            ),
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
                                  style:
                                      TextStyle(color: AppTheme.textDim)),
                            )
                          ],
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: devices.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
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
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: online ? AppTheme.accent : AppTheme.textDim,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.deviceName ?? device.deviceId,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(device.deviceId,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textDim)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Chip(
                        label: 'F1 ${device.f1On ? "ON" : "OFF"}',
                        on: device.f1On),
                    const SizedBox(width: 8),
                    _Chip(
                        label: 'F2 ${device.f2On ? "ON" : "OFF"}',
                        on: device.f2On),
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
