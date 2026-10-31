import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/brew_cycle.dart';
import '../services/appsync_client.dart';
import '../services/auth_service.dart';
import '../services/demo_data.dart';
import '../services/demo_mode.dart';
import '../services/errors.dart';
import '../services/history_store.dart';
import '../services/prefs.dart';
import '../theme.dart';
import '../utils/time_format.dart';
import '../widgets/glass_card.dart';

class BatchScreen extends StatefulWidget {
  final AuthService auth;
  final String deviceId;
  final String? deviceName;
  const BatchScreen({
    super.key,
    required this.auth,
    required this.deviceId,
    this.deviceName,
  });

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  late final AppSyncClient _client = AppSyncClient(widget.auth);
  Future<BrewCycleReport>? _future;
  bool _use24Hour = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadTimeFormat();
  }

  Future<BrewCycleReport> _load() {
    if (DemoMode.active) {
      return Future.value(DemoData.brewCycleReport());
    }
    return _client.brewCycleReport(widget.deviceId);
  }

  Future<void> _loadTimeFormat() async {
    final v = await AppPrefs.use24Hour();
    if (mounted) setState(() => _use24Hour = v);
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  Future<void> _editNotes(BrewStage stage) async {
    final controller = TextEditingController(text: stage.notes ?? '');
    String? text;
    try {
      text = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bg2,
          title: Text('Notes — ${stage.side ?? ''} ${stage.eventType ?? ''}'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Starter origin, flavour notes, pH readings…',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('Save')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (text == null) return;
    if (DemoMode.active) {
      _snack('Demo mode — note not saved.');
      return;
    }
    try {
      await _client.updateBrewCycleEventNotes(stage.id, text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notes saved.')),
      );
      _refresh();
    } on AppFailure catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(e.toString());
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final unit = await AppPrefs.unit();
      final samples = DemoMode.active
          ? DemoData.history()
          : await HistoryStore().load(widget.deviceId);
      if (samples.isEmpty) {
        _snack('No temperature history recorded yet for this device.');
        return;
      }
      final buf = StringBuffer()
        ..writeln('# ScobySense temperature history')
        ..writeln('# device: ${widget.deviceId}')
        ..writeln('# unit: °$unit')
        ..writeln('# exported: ${DateTime.now().toIso8601String()}')
        ..writeln('timestamp,f1_temp,f1_status,f2_temp,f2_status');
      for (final s in samples) {
        final iso = DateTime.fromMillisecondsSinceEpoch(s.ts * 1000, isUtc: true)
            .toIso8601String();
        final f1 = convertTemp(s.f1Temp, unit);
        final f2 = convertTemp(s.f2Temp, unit);
        buf.writeln(
          '$iso,${f1?.toStringAsFixed(2) ?? ''},${_csv(s.f1Status)},${f2?.toStringAsFixed(2) ?? ''},${_csv(s.f2Status)}',
        );
      }
      final safeName =
          widget.deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final filename =
          'scobysense_${safeName}_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-').split('.').first}.csv';
      final bytes = utf8.encode(buf.toString());
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: filename,
            mimeType: 'text/csv',
          ),
        ],
        fileNameOverrides: [filename],
        subject: 'ScobySense temperature history',
        text:
            'Temperature history for ${widget.deviceName ?? widget.deviceId}.',
      );
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static String _csv(String? v) {
    if (v == null || v.isEmpty) return '';
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deviceName != null
            ? 'Batches — ${widget.deviceName}'
            : 'Batches'),
        actions: [
          IconButton(
            tooltip: 'Export temperature history (CSV)',
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accent),
                  )
                : const Icon(Icons.ios_share),
            onPressed: _exporting ? null : _exportCsv,
          ),
        ],
      ),
      body: AppBackground(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppTheme.accent,
          child: FutureBuilder<BrewCycleReport>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return ListSkeleton(
                  count: 3,
                  tileBuilder: (_) => const GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBlock(height: 14, width: 120),
                        SizedBox(height: 10),
                        SkeletonBlock(height: 12, width: 200),
                        SizedBox(height: 6),
                        SkeletonBlock(height: 12, width: 160),
                      ],
                    ),
                  ),
                );
              }
              if (snap.hasError) {
                final err = snap.error;
                final msg =
                    err is AppFailure ? err.message : err.toString();
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    InlineErrorCard(message: msg, onRetry: _refresh),
                  ],
                );
              }
              final report = snap.data;
              if (report == null || report.total == 0) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    EmptyStateCard(
                      icon: Icons.science_outlined,
                      title: 'No brew cycles yet',
                      body:
                          'Start a brew from the device screen — F1 and F2 cycles will show up here with notes you can edit.',
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (report.activeF1 != null || report.activeF2 != null)
                    _activeCard(report),
                  const SizedBox(height: 16),
                  const SectionTitle('HISTORY'),
                  ...report.batches
                      .map((b) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _batchCard(b),
                          )),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _activeCard(BrewCycleReport r) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Active',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (r.activeF1 != null)
            _stageRow('F1 running', r.activeF1!, onEdit: _editNotes),
          if (r.activeF2 != null)
            _stageRow('F2 running', r.activeF2!, onEdit: _editNotes),
          if (r.activeF1 == null && r.activeF2 == null)
            const Text('No active stages.',
                style: TextStyle(color: AppTheme.textDim)),
        ],
      ),
    );
  }

  Widget _batchCard(BrewBatch b) {
    final tag = b.isComplete ? 'DONE' : 'IN PROGRESS';
    final tagColor = b.isComplete ? AppTheme.textDim : AppTheme.accent;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Batch #${b.batchNumber ?? '--'}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tagColor.withValues(alpha: 0.4)),
                ),
                child: Text(tag,
                    style: TextStyle(
                        color: tagColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (b.f1 != null) _stageRow('F1', b.f1!, onEdit: _editNotes),
          if (b.f2 != null) _stageRow('F2', b.f2!, onEdit: _editNotes),
        ],
      ),
    );
  }

  Widget _stageRow(String title, BrewStage s,
      {required void Function(BrewStage) onEdit}) {
    final start = _parseIso(s.timestamp);
    final end = _parseIso(s.expectedEndTime);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (s.status != null) s.status!,
                    if (s.durationDays != null) '${s.durationDays}d',
                    if (start != null) 'start ${_fmt(start)}',
                    if (end != null) 'end ${_fmt(end)}',
                  ].join(' · '),
                  style: const TextStyle(
                      color: AppTheme.textDim, fontSize: 11),
                ),
                if ((s.notes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(s.notes!,
                      style: const TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_note, size: 20),
            tooltip: 'Edit notes',
            onPressed: () => onEdit(s),
          ),
        ],
      ),
    );
  }

  DateTime? _parseIso(String? iso) =>
      (iso == null || iso.isEmpty) ? null : DateTime.tryParse(iso)?.toLocal();

  String _fmt(DateTime d) => formatAppDateTime(d, _use24Hour);
}
