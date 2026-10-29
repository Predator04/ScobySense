import 'package:flutter/material.dart';
import '../models/brew_cycle.dart';
import '../services/appsync_client.dart';
import '../services/auth_service.dart';
import '../services/errors.dart';
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

  @override
  void initState() {
    super.initState();
    _future = _client.brewCycleReport(widget.deviceId);
    _loadTimeFormat();
  }

  Future<void> _loadTimeFormat() async {
    final v = await AppPrefs.use24Hour();
    if (mounted) setState(() => _use24Hour = v);
  }

  Future<void> _refresh() async {
    final f = _client.brewCycleReport(widget.deviceId);
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  Future<void> _editNotes(BrewStage stage) async {
    final controller = TextEditingController(text: stage.notes ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KombuTheme.bg2,
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
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (text == null) return;
    try {
      await _client.updateBrewCycleEventNotes(stage.id, text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notes saved.')),
      );
      _refresh();
    } on KombuFailure catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(e.toString());
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deviceName != null
            ? 'Batches — ${widget.deviceName}'
            : 'Batches'),
      ),
      body: KombuBackground(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: KombuTheme.accent,
          child: FutureBuilder<BrewCycleReport>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                    child:
                        CircularProgressIndicator(color: KombuTheme.accent));
              }
              if (snap.hasError) {
                final err = snap.error;
                final msg =
                    err is KombuFailure ? err.message : err.toString();
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
                    GlassCard(
                      child: Text(
                        'No brew cycles yet for this device.',
                        style: TextStyle(color: KombuTheme.textDim),
                      ),
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
                style: TextStyle(color: KombuTheme.textDim)),
        ],
      ),
    );
  }

  Widget _batchCard(BrewBatch b) {
    final tag = b.isComplete ? 'DONE' : 'IN PROGRESS';
    final tagColor = b.isComplete ? KombuTheme.textDim : KombuTheme.accent;
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
                      color: KombuTheme.textDim, fontSize: 11),
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

  String _fmt(DateTime d) => formatKombuDateTime(d, _use24Hour);
}
