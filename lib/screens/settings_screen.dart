import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  const SettingsScreen({super.key, required this.onLogout});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _kUnit = 'temperature_unit';
  String _unit = 'C';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _unit = p.getString(_kUnit) ?? 'C');
  }

  Future<void> _setUnit(String u) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUnit, u);
    setState(() => _unit = u);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AppBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Temperature unit',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
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
                      'The device reports in its own unit; this is a display preference for charts.',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textDim)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Write control',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                      'Topic: <deviceId>/down/cmd. Commands: set_heater, set_sound, safety_stop, set_heating_time. The exact JSON payload wrapper is still being confirmed — see command_service.dart (PAYLOAD_WRAPPER_TODO).',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textDim)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Session',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                    onPressed: widget.onLogout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
