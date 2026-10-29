import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/command_service.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

/// Planned-only scheduling UI.
///
/// Saves F1/F2 start+stop times per device locally. Does NOT dispatch any
/// command — write control is still gated behind the `PAYLOAD_WRAPPER_TODO`
/// stub in command_service.dart. The screen shows what *would* be sent so the
/// shape can be reviewed before enabling.
class ScheduleScreen extends StatefulWidget {
  final String deviceId;
  const ScheduleScreen({super.key, required this.deviceId});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  TimeOfDay? _f1Start;
  TimeOfDay? _f1Stop;
  TimeOfDay? _f2Start;
  TimeOfDay? _f2Stop;
  bool _loaded = false;

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

    if (!mounted) return;
    setState(() {
      _f1Start = read(_kF1Start);
      _f1Stop = read(_kF1Stop);
      _f2Start = read(_kF2Start);
      _f2Stop = read(_kF2Stop);
      _loaded = true;
    });
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

  String _dryRunPayload() {
    final buffer = StringBuffer();
    void add(String side, String action, TimeOfDay? t) {
      if (t == null) return;
      final cmd =
          action == 'start' ? 'set_heater' : 'set_heater';
      final payload = buildCommandPayload(
        cmd,
        {'side': side, 'on': action == 'start'},
      );
      buffer.writeln('@ ${_fmt(t)} → ${payload.toString()}');
    }

    add('F1', 'start', _f1Start);
    add('F1', 'stop', _f1Stop);
    add('F2', 'start', _f2Start);
    add('F2', 'stop', _f2Stop);
    if (buffer.isEmpty) return '(no slots scheduled)';
    return buffer.toString().trimRight();
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
                        Row(children: [
                          Icon(Icons.warning_amber,
                              size: 16, color: KombuTheme.accent2),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Planned only',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ]),
                        SizedBox(height: 4),
                        Text(
                          'ScobySense saves these times locally and shows what would be sent. Nothing is dispatched — write control stays gated behind the payload-wrapper stub.',
                          style: TextStyle(
                              fontSize: 12, color: KombuTheme.textDim),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sideCard('F1', 'f1start', 'f1stop', _f1Start, _f1Stop),
                  const SizedBox(height: 14),
                  _sideCard('F2', 'f2start', 'f2stop', _f2Start, _f2Stop),
                  const SizedBox(height: 16),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Dry-run payload preview',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        const Text(
                            'What ScobySense would send if write control were enabled.',
                            style: TextStyle(
                                fontSize: 12, color: KombuTheme.textDim)),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: Text(
                            _dryRunPayload(),
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: KombuTheme.textDim),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
