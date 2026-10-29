import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/appsync_client.dart';
import '../services/auth_service.dart';
import '../services/command_service.dart';
import '../services/errors.dart';
import '../services/prefs.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

class ScheduleScreen extends StatefulWidget {
  final AuthService auth;
  final String deviceId;
  const ScheduleScreen({
    super.key,
    required this.auth,
    required this.deviceId,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late final CommandService _cmd =
      CommandService(AppSyncClient(widget.auth));
  TimeOfDay? _f1Start;
  TimeOfDay? _f1Stop;
  TimeOfDay? _f2Start;
  TimeOfDay? _f2Stop;
  int _f1Seconds = AppPrefs.defaultBrewSeconds('F1');
  int _f2Seconds = AppPrefs.defaultBrewSeconds('F2');
  bool _loaded = false;
  bool _busy = false;

  String get _kF1Start => 'sched:${widget.deviceId}:f1start';
  String get _kF1Stop => 'sched:${widget.deviceId}:f1stop';
  String get _kF2Start => 'sched:${widget.deviceId}:f2start';
  String get _kF2Stop => 'sched:${widget.deviceId}:f2stop';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    TimeOfDay? read(String k) {
      final s = p.getString(k);
      if (s == null) return null;
      final parts = s.split(':');
      if (parts.length != 2) return null;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      return TimeOfDay(hour: h, minute: m);
    }

    final f1Seconds = await AppPrefs.brewSeconds(widget.deviceId, 'F1');
    final f2Seconds = await AppPrefs.brewSeconds(widget.deviceId, 'F2');

    if (!mounted) return;
    setState(() {
      _f1Start = read(_kF1Start);
      _f1Stop = read(_kF1Stop);
      _f2Start = read(_kF2Start);
      _f2Stop = read(_kF2Stop);
      _f1Seconds = f1Seconds;
      _f2Seconds = f2Seconds;
      _loaded = true;
    });
  }

  static String _humanize(int totalSeconds) {
    if (totalSeconds <= 0) return '0m';
    final d = totalSeconds ~/ 86400;
    final h = (totalSeconds % 86400) ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final parts = <String>[];
    if (d > 0) parts.add('${d}d');
    if (h > 0) parts.add('${h}h');
    if (m > 0) parts.add('${m}m');
    if (parts.isEmpty) parts.add('<1m');
    return parts.join(' ');
  }

  Future<void> _save(String key, TimeOfDay? v) async {
    final p = await SharedPreferences.getInstance();
    if (v == null) {
      await p.remove(key);
    } else {
      await p.setString(key, '${v.hour}:${v.minute}');
    }
  }

  Future<void> _pick(String slot) async {
    final current = switch (slot) {
      'f1start' => _f1Start,
      'f1stop' => _f1Stop,
      'f2start' => _f2Start,
      _ => _f2Stop,
    };
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? TimeOfDay.now(),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    setState(() {
      switch (slot) {
        case 'f1start':
          _f1Start = picked;
          _save(_kF1Start, picked);
          break;
        case 'f1stop':
          _f1Stop = picked;
          _save(_kF1Stop, picked);
          break;
        case 'f2start':
          _f2Start = picked;
          _save(_kF2Start, picked);
          break;
        default:
          _f2Stop = picked;
          _save(_kF2Stop, picked);
      }
    });
  }

  Future<void> _clear(String slot) async {
    setState(() {
      switch (slot) {
        case 'f1start':
          _f1Start = null;
          _save(_kF1Start, null);
          break;
        case 'f1stop':
          _f1Stop = null;
          _save(_kF1Stop, null);
          break;
        case 'f2start':
          _f2Start = null;
          _save(_kF2Start, null);
          break;
        default:
          _f2Stop = null;
          _save(_kF2Stop, null);
      }
    });
  }

  String _fmt(TimeOfDay? t) {
    if (t == null) return 'Not set';
    final h12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final mm = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h12:$mm $period';
  }

  Future<void> _startBrew(String side) async {
    final seconds = side == 'F1' ? _f1Seconds : _f2Seconds;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _cmd.setBrewTimerSeconds(widget.deviceId, side, seconds);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('$side brew started: ${_humanize(seconds)}')),
      );
    } on KombuFailure catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: KombuTheme.danger,
          content: Text('$side brew failed: ${e.message}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: KombuTheme.danger,
          content: Text('$side brew failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schedule')),
      body: KombuBackground(
        child: !_loaded
            ? const Center(
                child: CircularProgressIndicator(color: KombuTheme.accent))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Start a brew',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text(
                          'Fires set_heater with the saved brew duration. Change the duration from the device screen.',
                          style: TextStyle(
                              fontSize: 12, color: KombuTheme.textDim),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _brewCard('F1', _f1Seconds),
                  const SizedBox(height: 14),
                  _brewCard('F2', _f2Seconds),
                  const SizedBox(height: 20),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Local reminders',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text(
                          'Saved on this phone only. The device accepts duration-based timers (not time-of-day), so these are personal reminders rather than dispatched schedules.',
                          style: TextStyle(
                              fontSize: 12, color: KombuTheme.textDim),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sideCard('F1', 'f1start', 'f1stop', _f1Start, _f1Stop),
                  const SizedBox(height: 14),
                  _sideCard('F2', 'f2start', 'f2stop', _f2Start, _f2Stop),
                ],
              ),
      ),
    );
  }

  Widget _brewCard(String side, int seconds) {
    final human = _humanize(seconds);
    final enabled = !_busy && seconds > 0;
    return GlassCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(side,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Saved duration: $human',
                    style: const TextStyle(
                        fontSize: 12, color: KombuTheme.textDim)),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: enabled ? () => _startBrew(side) : null,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text('Start $human'),
          ),
        ],
      ),
    );
  }

  Widget _sideCard(String label, String startSlot, String stopSlot,
      TimeOfDay? start, TimeOfDay? stop) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _row('Start', start, () => _pick(startSlot),
              onClear: () => _clear(startSlot)),
          _row('Stop', stop, () => _pick(stopSlot),
              onClear: () => _clear(stopSlot)),
        ],
      ),
    );
  }

  Widget _row(String label, TimeOfDay? v, VoidCallback onPick,
      {required VoidCallback onClear}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: const TextStyle(color: KombuTheme.textDim)),
          ),
          Expanded(child: Text(_fmt(v))),
          TextButton(
              onPressed: onPick,
              child: Text(v == null ? 'Set' : 'Change')),
          if (v != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClear,
              tooltip: 'Clear',
            ),
        ],
      ),
    );
  }
}
