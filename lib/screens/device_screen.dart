import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/appsync_client.dart';
import '../services/auth_service.dart';
import '../services/command_service.dart';
import '../services/errors.dart';
import '../services/history_store.dart';
import '../services/notification_service.dart';
import '../services/prefs.dart';
import '../services/subscription_client.dart';
import '../theme.dart';
import '../utils/time_format.dart';
import 'batch_screen.dart';
import 'schedule_screen.dart';
import '../widgets/glass_card.dart';

class DeviceScreen extends StatefulWidget {
  final AuthService auth;
  final BrewerDevice initial;
  const DeviceScreen({super.key, required this.auth, required this.initial});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  late final AppSyncClient _client = AppSyncClient(widget.auth);
  late final CommandService _cmd = CommandService(_client);
  late final DeviceSubscriptionClient _sub =
      DeviceSubscriptionClient(widget.auth);
  StreamSubscription<BrewerDevice>? _subListen;
  final _history = HistoryStore();
  late BrewerDevice _device = widget.initial;
  Timer? _poll;
  bool _liveConnected = false;
  List<Map<String, dynamic>> _alertRules = const [];
  DateTime? _lastF1Expected;
  DateTime? _lastF2Expected;
  bool _busy = false;
  String? _ack;
  String? _err;
  List<TempSample> _samples = const [];
  bool _detailsOpen = false;
  bool _controlOpen = false;
  String _unit = 'F';
  bool _use24Hour = false;

  @override
  void initState() {
    super.initState();
    _loadUnit();
    _loadTimeFormat();
    _loadHistory();
    _loadAlertRules();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
    _startLive();
  }

  Future<void> _startLive() async {
    _subListen = _sub.updates.listen(_onLiveUpdate);
    await _sub.start();
    if (mounted) setState(() => _liveConnected = true);
  }

  void _onLiveUpdate(BrewerDevice d) {
    if (d.deviceId != _device.deviceId) return;
    final sample = TempSample(
      ts: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      f1Temp: d.f1Temp,
      f2Temp: d.f2Temp,
      f1Status: d.f1Status,
      f2Status: d.f2Status,
    );
    _history.append(d.deviceId, sample);
    _checkNotifications(d);
    if (!mounted) return;
    setState(() {
      _device = d;
      _liveConnected = true;
      _err = null;
    });
  }

  void _checkNotifications(BrewerDevice d) {
    NotificationService.instance.evaluate(d, rules: _alertRules);
    DateTime? parse(String? iso) =>
        (iso == null || iso.isEmpty) ? null : DateTime.tryParse(iso);
    final f1New = parse(d.f1RemainingTime);
    final f2New = parse(d.f2RemainingTime);
    final now = DateTime.now();

    if (f1New != null && _lastF1Expected != null) {
      final wasFuture = _lastF1Expected!.isAfter(now.subtract(
          const Duration(minutes: 2)));
      if (!f1New.isAfter(now) && wasFuture) {
        NotificationService.instance.brewTimerDone(d, 'F1');
      }
    }
    if (f2New != null && _lastF2Expected != null) {
      final wasFuture = _lastF2Expected!.isAfter(now.subtract(
          const Duration(minutes: 2)));
      if (!f2New.isAfter(now) && wasFuture) {
        NotificationService.instance.brewTimerDone(d, 'F2');
      }
    }
    _lastF1Expected = f1New;
    _lastF2Expected = f2New;
  }

  Future<void> _loadUnit() async {
    final u = await AppPrefs.unit();
    if (mounted) setState(() => _unit = u);
  }

  Future<void> _loadTimeFormat() async {
    final v = await AppPrefs.use24Hour();
    if (mounted) setState(() => _use24Hour = v);
  }

  Future<void> _loadAlertRules() async {
    try {
      final rules = await _client.listAlertRules();
      if (mounted) setState(() => _alertRules = rules);
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    _subListen?.cancel();
    _sub.stop();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final s = await _history.load(_device.deviceId);
    if (mounted) setState(() => _samples = s);
  }

  Future<void> _refresh() async {
    try {
      final devices = await _client.listDevices();
      final match = devices.firstWhere(
        (d) => d.deviceId == _device.deviceId,
        orElse: () => _device,
      );
      final sample = TempSample(
        ts: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        f1Temp: match.f1Temp,
        f2Temp: match.f2Temp,
        f1Status: match.f1Status,
        f2Status: match.f2Status,
      );
      await _history.append(match.deviceId, sample);
      final hist = await _history.load(match.deviceId);
      _checkNotifications(match);
      if (!mounted) return;
      setState(() {
        _device = match;
        _samples = hist;
        _err = null;
      });
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() => _err = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    }
  }

  Future<void> _run(String label, Future<String> Function() op) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: Text(label),
        content: const Text(
            'Control commands are still being verified and could disrupt an active ferment. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _ack = null;
      _err = null;
    });
    try {
      final r = await op();
      if (!mounted) return;
      setState(() => _ack = '$label: $r');
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() => _err = '$label: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$label: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_device.deviceName ?? _device.deviceId),
        actions: [
          IconButton(
            tooltip: 'Batches',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BatchScreen(
                  auth: widget.auth,
                  deviceId: _device.deviceId,
                  deviceName: _device.deviceName,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Schedule',
            icon: const Icon(Icons.schedule),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ScheduleScreen(deviceId: _device.deviceId),
              ),
            ),
          ),
          IconButton(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: AppBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusCard(),
            const SizedBox(height: 14),
            _controlCard(),
            const SizedBox(height: 14),
            if (_samples.length > 1) _chartCard(),
            if (_ack != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: GlassCard(
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppTheme.accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('ACK: $_ack',
                            style:
                                const TextStyle(color: AppTheme.accent)),
                      ),
                    ],
                  ),
                ),
              ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: InlineErrorCard(message: _err!, onRetry: _refresh),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    String ft(double? t) => formatTemp(t, _unit);
    String formatRemaining(String? iso) {
      if (iso == null || iso.isEmpty) return '--';
      final d = DateTime.tryParse(iso);
      if (d == null) return iso;
      return formatAppDateTime(d.toLocal(), _use24Hour);
    }

    final online = (_device.status ?? '').toLowerCase() == 'online';
    final statusColor = online ? AppTheme.accent : AppTheme.accent2;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Status',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            if (_liveConnected)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.circle, size: 7, color: AppTheme.accent),
                    SizedBox(width: 4),
                    Text('LIVE',
                        style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 9,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: statusColor.withValues(alpha: 0.5), width: 1),
              ),
              child: Text(_device.status ?? 'unknown',
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  label: 'F1',
                  valueTop: ft(_device.f1Temp),
                  valueBot: _device.f1On ? 'HEATING' : 'off',
                  accent: _device.f1On,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBlock(
                  label: 'F2',
                  valueTop: ft(_device.f2Temp),
                  valueBot: _device.f2On ? 'HEATING' : 'off',
                  accent: _device.f2On,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _summaryRow(formatRemaining),
          _ExpandToggle(
            open: _detailsOpen,
            onToggle: () => setState(() => _detailsOpen = !_detailsOpen),
            label: 'Details',
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _detailsOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  _kv('F1 remaining', formatRemaining(_device.f1RemainingTime)),
                  _kv('F2 remaining', formatRemaining(_device.f2RemainingTime)),
                  _kv('WiFi',
                      (_device.wifiConnected ?? false) ? 'connected' : 'offline'),
                  _kv('Firmware', _device.firmwareVersion ?? '--'),
                  _kv('Last seen', _device.lastSeen ?? '--'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String Function(String?) fmt) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 14, color: AppTheme.textDim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _device.f1On
                  ? 'F1 ends ${fmt(_device.f1RemainingTime)}'
                  : _device.f2On
                      ? 'F2 ends ${fmt(_device.f2RemainingTime)}'
                      : 'Idle',
              style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(k, style: const TextStyle(color: AppTheme.textDim)),
          const Spacer(),
          Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _controlCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Text('Control',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            SizedBox(width: 8),
            Icon(Icons.warning_amber, size: 16, color: AppTheme.accent2),
          ]),
          const SizedBox(height: 4),
          const Text(
              'Controls are still being verified. Commands may be rejected or disrupt a ferment.',
              style: TextStyle(fontSize: 12, color: AppTheme.textDim)),
          _ExpandToggle(
            open: _controlOpen,
            onToggle: () => setState(() => _controlOpen = !_controlOpen),
            label: 'Show controls',
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _controlOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _btn(
                    _device.f1On ? 'Stop F1' : 'Start F1',
                    () => _run(_device.f1On ? 'Stop F1' : 'Start F1',
                        () => _cmd.setHeaterF1(_device.deviceId, !_device.f1On)),
                  ),
                  _btn(
                    _device.f2On ? 'Stop F2' : 'Start F2',
                    () => _run(_device.f2On ? 'Stop F2' : 'Start F2',
                        () => _cmd.setHeaterF2(_device.deviceId, !_device.f2On)),
                  ),
                  _btn('F1 timer 3d',
                      () => _run('F1 timer 3d',
                          () => _cmd.setBrewTimer(_device.deviceId, 'F1', 3))),
                  _btn('F2 timer 7d',
                      () => _run('F2 timer 7d',
                          () => _cmd.setBrewTimer(_device.deviceId, 'F2', 7))),
                  _btn('Sound on',
                      () => _run('Sound on',
                          () => _cmd.setSound(_device.deviceId, true))),
                  _btn('Sound off',
                      () => _run('Sound off',
                          () => _cmd.setSound(_device.deviceId, false))),
                  _dangerBtn('Safety stop',
                      () => _run('Safety stop',
                          () => _cmd.safetyStop(_device.deviceId))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) => ElevatedButton(
        onPressed: _busy ? null : onTap,
        child: Text(label),
      );

  Widget _dangerBtn(String label, VoidCallback onTap) => ElevatedButton(
        onPressed: _busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.danger,
          foregroundColor: Colors.white,
        ),
        child: Text(label),
      );

  Widget _chartCard() {
    final t0 = _samples.first.ts.toDouble();
    List<FlSpot> spots(double? Function(TempSample) pick) => _samples
        .where((s) => pick(s) != null)
        .map((s) => FlSpot(
              (s.ts - t0).toDouble() / 60,
              convertTemp(pick(s), _unit)!,
            ))
        .toList();

    final f1 = spots((s) => s.f1Temp);
    final f2 = spots((s) => s.f2Temp);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Temperature history',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineBarsData: [
                  if (f1.isNotEmpty)
                    LineChartBarData(
                      spots: f1,
                      color: AppTheme.accent2,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                  if (f2.isNotEmpty)
                    LineChartBarData(
                      spots: f2,
                      color: AppTheme.accent,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: const [
            _LegendDot(c: AppTheme.accent2, label: 'F1'),
            SizedBox(width: 12),
            _LegendDot(c: AppTheme.accent, label: 'F2'),
          ]),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String valueTop;
  final String valueBot;
  final bool accent;
  const _StatBlock({
    required this.label,
    required this.valueTop,
    required this.valueBot,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: accent
              ? [
                  AppTheme.accent.withValues(alpha: 0.14),
                  AppTheme.accent.withValues(alpha: 0.04),
                ]
              : [
                  Colors.white.withValues(alpha: 0.04),
                  Colors.white.withValues(alpha: 0.02),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: accent
                ? AppTheme.accent.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(valueTop,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700)),
          Text(valueBot,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: accent ? AppTheme.accent : AppTheme.textDim)),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color c;
  final String label;
  const _LegendDot({required this.c, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);
  }
}

class _ExpandToggle extends StatelessWidget {
  final bool open;
  final VoidCallback onToggle;
  final String label;
  const _ExpandToggle(
      {required this.open, required this.onToggle, required this.label});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w600)),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.expand_more,
                  size: 18, color: AppTheme.accent),
            ),
          ],
        ),
      ),
    );
  }
}
