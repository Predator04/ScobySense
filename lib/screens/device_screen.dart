import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/device.dart';
import '../services/appsync_client.dart';
import '../services/auth_service.dart';
import '../services/command_service.dart';
import '../services/history_store.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

class DeviceScreen extends StatefulWidget {
  final AuthService auth;
  final KombuDevice initial;
  const DeviceScreen({super.key, required this.auth, required this.initial});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  late final AppSyncClient _client = AppSyncClient(widget.auth);
  late final CommandService _cmd = CommandService(_client);
  final _history = HistoryStore();
  late KombuDevice _device = widget.initial;
  Timer? _poll;
  bool _busy = false;
  String? _ack;
  String? _err;
  List<TempSample> _samples = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
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
      if (!mounted) return;
      setState(() {
        _device = match;
        _samples = hist;
        _err = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    }
  }

  Future<void> _run(String label, Future<String> Function() op) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KombuTheme.bg2,
        title: Text(label),
        content: const Text(
            'The pushCommand payload wrapper is not fully confirmed. If an active ferment is running, this could disrupt it. Continue?'),
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
      setState(() => _ack = '$label: $r');
    } catch (e) {
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
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: KombuBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusCard(),
            const SizedBox(height: 12),
            _controlCard(),
            const SizedBox(height: 12),
            if (_samples.length > 1) _chartCard(),
            if (_ack != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: GlassCard(
                  child: Text('ACK: $_ack',
                      style: const TextStyle(color: KombuTheme.accent)),
                ),
              ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: GlassCard(
                  child: Text(_err!,
                      style: const TextStyle(color: KombuTheme.danger)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    final unit = _device.temperatureUnit ?? 'C';
    String formatTemp(double? t) =>
        t == null ? '--' : '${t.toStringAsFixed(1)}°$unit';
    String formatRemaining(String? iso) {
      if (iso == null) return '--';
      final d = DateTime.tryParse(iso);
      if (d == null) return iso;
      return DateFormat('MMM d, HH:mm').format(d.toLocal());
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Status',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: KombuTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: KombuTheme.accent.withValues(alpha: 0.4)),
              ),
              child: Text(_device.status ?? 'unknown',
                  style: const TextStyle(
                      color: KombuTheme.accent, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  label: 'F1',
                  valueTop: formatTemp(_device.f1Temp),
                  valueBot: _device.f1On ? 'HEATING' : 'off',
                  accent: _device.f1On,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBlock(
                  label: 'F2',
                  valueTop: formatTemp(_device.f2Temp),
                  valueBot: _device.f2On ? 'HEATING' : 'off',
                  accent: _device.f2On,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _kv('F1 remaining', formatRemaining(_device.f1RemainingTime)),
          _kv('F2 remaining', formatRemaining(_device.f2RemainingTime)),
          _kv('WiFi', (_device.wifiConnected ?? false) ? 'connected' : 'offline'),
          _kv('Firmware', _device.firmwareVersion ?? '--'),
          _kv('Last seen',
              _device.lastSeen == null ? '--' : _device.lastSeen!),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(k, style: const TextStyle(color: KombuTheme.textDim)),
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            SizedBox(width: 8),
            Icon(Icons.warning_amber, size: 16, color: KombuTheme.accent2),
          ]),
          const SizedBox(height: 4),
          const Text(
              'Payload wrapper not yet confirmed. Writes may be rejected or disrupt a ferment.',
              style: TextStyle(fontSize: 12, color: KombuTheme.textDim)),
          const SizedBox(height: 12),
          Wrap(
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
          backgroundColor: KombuTheme.danger,
          foregroundColor: Colors.white,
        ),
        child: Text(label),
      );

  Widget _chartCard() {
    final t0 = _samples.first.ts.toDouble();
    List<FlSpot> spots(double? Function(TempSample) pick) => _samples
        .where((s) => pick(s) != null)
        .map((s) => FlSpot((s.ts - t0).toDouble() / 60, pick(s)!))
        .toList();

    final f1 = spots((s) => s.f1Temp);
    final f2 = spots((s) => s.f2Temp);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Temperature history',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                      color: KombuTheme.accent2,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                  if (f2.isNotEmpty)
                    LineChartBarData(
                      spots: f2,
                      color: KombuTheme.accent,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: const [
            _LegendDot(c: KombuTheme.accent2, label: 'F1'),
            SizedBox(width: 12),
            _LegendDot(c: KombuTheme.accent, label: 'F2'),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: KombuTheme.textDim, fontSize: 12)),
          const SizedBox(height: 4),
          Text(valueTop,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700)),
          Text(valueBot,
              style: TextStyle(
                  fontSize: 12,
                  color:
                      accent ? KombuTheme.accent : KombuTheme.textDim)),
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
