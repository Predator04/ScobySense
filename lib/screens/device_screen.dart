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
import 'recipes_screen.dart';
import 'schedule_screen.dart';
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
  late final DeviceSubscriptionClient _sub =
      DeviceSubscriptionClient(widget.auth);
  StreamSubscription<KombuDevice>? _subListen;
  final _history = HistoryStore();
  late KombuDevice _device = widget.initial;
  Timer? _poll;
  Timer? _ticker;
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
  String? _localName;
  int _f1Days = AppPrefs.defaultF1Days;
  int _f2Days = AppPrefs.defaultF2Days;

  @override
  void initState() {
    super.initState();
    _loadUnit();
    _loadTimeFormat();
    _loadHistory();
    _loadAlertRules();
    _loadLocalName();
    _loadBrewDays();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
    // Keep the countdown fresh between polls.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _startLive();
  }

  Future<void> _startLive() async {
    _subListen = _sub.updates.listen(_onLiveUpdate);
    await _sub.start();
    if (mounted) setState(() => _liveConnected = true);
  }

  void _onLiveUpdate(KombuDevice d) {
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

  void _checkNotifications(KombuDevice d) {
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

  Future<void> _loadLocalName() async {
    final n = await AppPrefs.deviceDisplayName(_device.deviceId);
    if (mounted) setState(() => _localName = n);
  }

  Future<void> _loadBrewDays() async {
    final f1 = await AppPrefs.brewDays(_device.deviceId, 'F1');
    final f2 = await AppPrefs.brewDays(_device.deviceId, 'F2');
    if (mounted) {
      setState(() {
        _f1Days = f1;
        _f2Days = f2;
      });
    }
  }

  String get _displayName {
    final n = _localName;
    if (n != null && n.isNotEmpty) return n;
    final remote = _device.deviceName;
    if (remote != null && remote.isNotEmpty) return remote;
    return _device.deviceId;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ticker?.cancel();
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
    } on KombuFailure catch (e) {
      if (!mounted) return;
      setState(() => _err = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    }
  }

  Future<void> _run(String label, Future<bool> Function() op) async {
    setState(() {
      _busy = true;
      _ack = null;
      _err = null;
    });
    try {
      await op();
      if (!mounted) return;
      setState(() => _ack = '$label sent');
    } on KombuFailure catch (e) {
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
        title: InkWell(
          onTap: _promptRename,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(_displayName, overflow: TextOverflow.ellipsis),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Rename device',
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: _promptRename,
          ),
          IconButton(
            tooltip: 'Batches',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BatchScreen(
                  auth: widget.auth,
                  deviceId: _device.deviceId,
                  deviceName: _displayName,
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
                builder: (_) => ScheduleScreen(
                  auth: widget.auth,
                  deviceId: _device.deviceId,
                ),
              ),
            ),
          ),
          IconButton(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: KombuBackground(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: KombuTheme.accent,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _statusCard(),
              const SizedBox(height: 14),
              _recipesButton(),
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
                            color: KombuTheme.accent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('ACK: $_ack',
                              style:
                                  const TextStyle(color: KombuTheme.accent)),
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
      ),
    );
  }

  Future<void> _promptRename() async {
    final controller = TextEditingController(text: _localName ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KombuTheme.bg2,
        title: const Text('Rename device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Display name',
                hintText: _device.deviceName ?? _device.deviceId,
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 8),
            const Text(
              'Stored on this device only — does not change the name on Kombu\'s servers.',
              style: TextStyle(color: KombuTheme.textDim, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          if ((_localName ?? '').isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Reset'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final trimmed = result.trim();
    await AppPrefs.setDeviceDisplayName(
        _device.deviceId, trimmed.isEmpty ? null : trimmed);
    if (!mounted) return;
    setState(() => _localName = trimmed.isEmpty ? null : trimmed);
  }

  Future<void> _showBrewDurationSheet(String side) async {
    final isF1 = side.toUpperCase() == 'F1';
    final minDays = 1;
    final maxDays = 30;
    final current = isF1 ? _f1Days : _f2Days;
    int selected = current.clamp(minDays, maxDays);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KombuTheme.bg2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
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
                    child: const Icon(Icons.timer_outlined,
                        color: KombuTheme.accent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Set $side brew duration',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Currently saved: $current ${current == 1 ? "day" : "days"} '
                '(range $minDays–$maxDays)',
                style: const TextStyle(
                    color: KombuTheme.textDim, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int d = minDays; d <= maxDays; d++)
                    ChoiceChip(
                      label: Text('${d}d'),
                      selected: selected == d,
                      onSelected: (_) => setSheet(() => selected = d),
                      selectedColor:
                          KombuTheme.accent.withValues(alpha: 0.25),
                      labelStyle: TextStyle(
                        color: selected == d
                            ? KombuTheme.accent
                            : KombuTheme.text,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor:
                          Colors.white.withValues(alpha: 0.05),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: selected == d
                              ? KombuTheme.accent
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await AppPrefs.setBrewDays(
                            _device.deviceId, side, selected);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        setState(() {
                          if (isF1) {
                            _f1Days = selected;
                          } else {
                            _f2Days = selected;
                          }
                        });
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await _cmd.setBrewTimer(
                              _device.deviceId, side, selected);
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                  '$side brew started: ${selected}d'),
                            ),
                          );
                          setState(() => _ack = '$side brew $selected d sent');
                        } on KombuFailure catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: KombuTheme.danger,
                              content:
                                  Text('$side brew failed: ${e.message}'),
                            ),
                          );
                          setState(() => _err = '$side brew: ${e.message}');
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: KombuTheme.danger,
                              content: Text('$side brew failed: $e'),
                            ),
                          );
                          setState(() => _err = '$side brew: $e');
                        }
                      },
                      child: const Text('Start brew'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCountdown(DateTime end) {
    final diff = end.difference(DateTime.now());
    if (diff.isNegative || diff == Duration.zero) return 'overdue';
    if (diff.inDays >= 1) {
      final h = diff.inHours.remainder(24);
      return '${diff.inDays}d ${h}h left';
    }
    if (diff.inHours >= 1) {
      final m = diff.inMinutes.remainder(60);
      return '${diff.inHours}h ${m}m left';
    }
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m left';
    return '<1m left';
  }

  Widget _statusCard() {
    String ft(double? t) => formatTemp(t, _unit);
    String formatRemaining(String? iso) {
      if (iso == null || iso.isEmpty) return '--';
      final d = DateTime.tryParse(iso);
      if (d == null) return iso;
      return formatKombuDateTime(d.toLocal(), _use24Hour);
    }

    final online = (_device.status ?? '').toLowerCase() == 'online';
    final statusColor = online ? KombuTheme.accent : KombuTheme.accent2;

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
                  color: KombuTheme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: KombuTheme.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.circle, size: 7, color: KombuTheme.accent),
                    SizedBox(width: 4),
                    Text('LIVE',
                        style: TextStyle(
                            color: KombuTheme.accent,
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
                  footer: 'Brew: ${_f1Days}d · tap to change',
                  onTap: () => _showBrewDurationSheet('F1'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBlock(
                  label: 'F2',
                  valueTop: ft(_device.f2Temp),
                  valueBot: _device.f2On ? 'HEATING' : 'off',
                  accent: _device.f2On,
                  footer: 'Brew: ${_f2Days}d · tap to change',
                  onTap: () => _showBrewDurationSheet('F2'),
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
                  _kv('WiFi (device-reported)', _wifiLabel(online)),
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

  String _wifiLabel(bool online) {
    final connected = _device.wifiConnected ?? false;
    if (connected) return 'connected';
    if (online) return 'offline · via cloud';
    return 'offline';
  }

  Widget _summaryRow(String Function(String?) fmt) {
    String? iso;
    String side = '';
    if (_device.f1On) {
      iso = _device.f1RemainingTime;
      side = 'F1';
    } else if (_device.f2On) {
      iso = _device.f2RemainingTime;
      side = 'F2';
    }

    String text;
    if (iso == null || iso.isEmpty) {
      text = 'Idle';
    } else {
      final end = DateTime.tryParse(iso)?.toLocal();
      final absolute = fmt(iso);
      if (end != null) {
        text = '$side ends $absolute · ${_formatCountdown(end)}';
      } else {
        text = '$side ends $absolute';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 14, color: KombuTheme.textDim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: KombuTheme.textDim),
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

  Widget _recipesButton() {
    return _Recipes3DButton(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RecipesScreen()),
      ),
    );
  }

  Widget _controlCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Control',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                  _btn('Start F1 (${_f1Days}d)',
                      () => _run('Start F1 ${_f1Days}d',
                          () => _cmd.setBrewTimer(
                              _device.deviceId, 'F1', _f1Days))),
                  _btn('Start F2 (${_f2Days}d)',
                      () => _run('Start F2 ${_f2Days}d',
                          () => _cmd.setBrewTimer(
                              _device.deviceId, 'F2', _f2Days))),
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
          backgroundColor: KombuTheme.danger,
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
  final String? footer;
  final VoidCallback? onTap;
  const _StatBlock({
    required this.label,
    required this.valueTop,
    required this.valueBot,
    required this.accent,
    this.footer,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: accent
              ? [
                  KombuTheme.accent.withValues(alpha: 0.14),
                  KombuTheme.accent.withValues(alpha: 0.04),
                ]
              : [
                  Colors.white.withValues(alpha: 0.04),
                  Colors.white.withValues(alpha: 0.02),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: accent
                ? KombuTheme.accent.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(
                      color: KombuTheme.textDim,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              if (onTap != null) ...[
                const Spacer(),
                Icon(Icons.edit_calendar_outlined,
                    size: 14,
                    color:
                        KombuTheme.textDim.withValues(alpha: 0.8)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(valueTop,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700)),
          Text(valueBot,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: accent ? KombuTheme.accent : KombuTheme.textDim)),
          if (footer != null) ...[
            const SizedBox(height: 6),
            Text(footer!,
                style: const TextStyle(
                    fontSize: 10.5,
                    color: KombuTheme.textDim,
                    letterSpacing: 0.2)),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: content,
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

class _Recipes3DButton extends StatefulWidget {
  final VoidCallback onTap;
  const _Recipes3DButton({required this.onTap});

  @override
  State<_Recipes3DButton> createState() => _Recipes3DButtonState();
}

class _Recipes3DButtonState extends State<_Recipes3DButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        scale: _pressed ? 0.98 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: KombuTheme.accent.withValues(alpha: _pressed ? 0.18 : 0.35),
                blurRadius: _pressed ? 14 : 30,
                spreadRadius: -4,
                offset: Offset(0, _pressed ? 4 : 14),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: _pressed ? 0.25 : 0.5),
                blurRadius: _pressed ? 10 : 24,
                spreadRadius: -6,
                offset: Offset(0, _pressed ? 3 : 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: widget.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      KombuTheme.accent.withValues(alpha: 0.28),
                      KombuTheme.accent2.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0.04),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                  border: Border.all(
                    color: KombuTheme.accent.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            KombuTheme.accent,
                            KombuTheme.accent.withValues(alpha: 0.65),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                KombuTheme.accent.withValues(alpha: 0.55),
                            blurRadius: 18,
                            spreadRadius: -2,
                          ),
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.15),
                            blurRadius: 4,
                            spreadRadius: -2,
                            offset: const Offset(-2, -2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.menu_book,
                        color: Color(0xFF04070A),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recipes',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: KombuTheme.text,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  offset: Offset(0, 1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Browse built-in kombucha + soda recipes, or add your own.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: KombuTheme.text.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                      child: const Icon(Icons.restaurant_menu,
                          color: KombuTheme.accent, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
                    color: KombuTheme.accent,
                    fontWeight: FontWeight.w600)),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.expand_more,
                  size: 18, color: KombuTheme.accent),
            ),
          ],
        ),
      ),
    );
  }
}
