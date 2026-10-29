import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/errors.dart';
import '../services/prefs.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/update_dialog.dart';
import 'privacy_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  final UpdateService updater;
  const SettingsScreen({
    super.key,
    required this.onLogout,
    required this.updater,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _unit = 'F';
  bool _notif = true;
  PackageInfo? _info;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final unit = await AppPrefs.unit();
    final notif = await AppPrefs.notifications();
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _unit = unit;
      _notif = notif;
      _info = info;
    });
  }

  Future<void> _setUnit(String u) async {
    await AppPrefs.setUnit(u);
    if (!mounted) return;
    setState(() => _unit = u);
  }

  Future<void> _setNotif(bool v) async {
    await AppPrefs.setNotifications(v);
    if (!mounted) return;
    setState(() => _notif = v);
  }

  Future<void> _openRepo() async {
    final url = Uri.parse('https://github.com/Predator04/ScobySense');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _snack('Could not open browser.');
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checking = true);
    try {
      final release = await widget.updater.checkForUpdate();
      if (!mounted) return;
      if (release == null) {
        _snack('You\'re on the latest version.');
      } else {
        final info = _info ?? await PackageInfo.fromPlatform();
        if (!mounted) return;
        await showUpdateFlow(
          context,
          widget.updater,
          release,
          currentVersion: '${info.version}+${info.buildNumber}',
        );
      }
    } on KombuFailure catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final version = _info?.version ?? '--';
    final build = _info?.buildNumber ?? '--';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: KombuBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionTitle('APP'),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(colors: [
                            KombuTheme.accent,
                            KombuTheme.accent2,
                          ]),
                        ),
                        child: const Icon(Icons.local_drink,
                            color: Color(0xFF04070A), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ScobySense',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            Text('Version $version (build $build)',
                                style: const TextStyle(
                                    color: KombuTheme.textDim,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _checking ? null : _checkForUpdates,
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF04070A)))
                          : const Icon(Icons.cloud_download, size: 18),
                      label: Text(_checking
                          ? 'Checking…'
                          : 'Check for updates'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Updates download directly from GitHub releases. Android will show its standard install prompt.',
                    style: TextStyle(
                        fontSize: 12, color: KombuTheme.textDim),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('PREFERENCES'),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Temperature unit',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'C', label: Text('Celsius')),
                      ButtonSegment(value: 'F', label: Text('Fahrenheit')),
                    ],
                    selected: {_unit},
                    onSelectionChanged: (s) => _setUnit(s.first),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'Device readings arrive in Fahrenheit (labelled "C" in firmware). Switching to Celsius converts for display only.',
                      style: TextStyle(
                          fontSize: 12, color: KombuTheme.textDim)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('NOTIFICATIONS'),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Alerts + brew timer',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Switch(value: _notif, onChanged: _setNotif),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                      'Local only, fires while ScobySense is running. The Kombu backend separately handles server-side push via Firebase.',
                      style: TextStyle(
                          fontSize: 12, color: KombuTheme.textDim)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('ABOUT'),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What\'s inside',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const _Feature(
                      icon: Icons.devices,
                      text: 'Live device status + heater state'),
                  const _Feature(
                      icon: Icons.bolt,
                      text: 'Real-time AppSync subscription (polling fallback)'),
                  const _Feature(
                      icon: Icons.show_chart,
                      text: 'Local temperature history + chart'),
                  const _Feature(
                      icon: Icons.science_outlined,
                      text: 'Batch tracker for F1/F2 brew cycles'),
                  const _Feature(
                      icon: Icons.notifications_active,
                      text: 'Local alerts when thresholds are crossed'),
                  const _Feature(
                      icon: Icons.menu_book,
                      text: 'Built-in kombucha + soda recipes'),
                  const _Feature(
                      icon: Icons.cloud_download,
                      text: 'In-app updates from GitHub releases'),
                  const _Feature(
                      icon: Icons.lock,
                      text: 'Credentials go only to Amazon Cognito'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PrivacyScreen())),
                          icon: const Icon(Icons.privacy_tip_outlined,
                              size: 16),
                          label: const Text('Privacy'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openRepo,
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('GitHub'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('WRITE CONTROL'),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Device write path',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 4),
                  Text(
                      'Topic: <deviceId>/down/cmd. Commands: set_heater, set_sound, safety_stop, set_heating_time. The exact JSON payload wrapper is still being confirmed — see command_service.dart (PAYLOAD_WRAPPER_TODO).',
                      style: TextStyle(
                          fontSize: 12, color: KombuTheme.textDim)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('SESSION'),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KombuTheme.danger,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
                      onPressed: widget.onLogout,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Feature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: KombuTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: KombuTheme.text)),
          ),
        ],
      ),
    );
  }
}
