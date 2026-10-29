import 'dart:async';
import 'package:flutter/material.dart';
import '../services/errors.dart';
import '../services/update_service.dart';
import '../theme.dart';
import 'glass_card.dart';

enum _UpdateUiState { prompt, downloading, done, failed }

Future<void> showUpdateFlow(
  BuildContext context,
  UpdateService service,
  ReleaseInfo release, {
  required String currentVersion,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => UpdatePromptDialog(
      service: service,
      release: release,
      currentVersion: currentVersion,
    ),
  );
}

class UpdatePromptDialog extends StatefulWidget {
  final UpdateService service;
  final ReleaseInfo release;
  final String currentVersion;
  const UpdatePromptDialog({
    super.key,
    required this.service,
    required this.release,
    required this.currentVersion,
  });

  @override
  State<UpdatePromptDialog> createState() => _UpdatePromptDialogState();
}

class _UpdatePromptDialogState extends State<UpdatePromptDialog> {
  _UpdateUiState _state = _UpdateUiState.prompt;
  DownloadProgress _progress =
      const DownloadProgress(received: 0, total: 0, bytesPerSec: 0, eta: Duration.zero);
  String? _error;

  Future<void> _start() async {
    setState(() {
      _state = _UpdateUiState.downloading;
      _error = null;
    });
    try {
      final file = await widget.service.downloadApk(
        widget.release,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      await widget.service.installApk(file);
      if (!mounted) return;
      setState(() => _state = _UpdateUiState.done);
    } on UpdateCancelled {
      if (!mounted) return;
      Navigator.of(context).pop();
    } on KombuFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _UpdateUiState.failed;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _UpdateUiState.failed;
        _error = e.toString();
      });
    }
  }

  void _cancel() {
    widget.service.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: switch (_state) {
            _UpdateUiState.prompt => _buildPrompt(context),
            _UpdateUiState.downloading => _buildDownloading(context),
            _UpdateUiState.done => _buildDone(context),
            _UpdateUiState.failed => _buildFailed(context),
          },
        ),
      ),
    );
  }

  Widget _buildPrompt(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [KombuTheme.accent, KombuTheme.accent2],
              ),
            ),
            child: const Icon(Icons.download, color: Color(0xFF04070A)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Update available',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 16),
        Text(
          '${widget.currentVersion} → ${widget.release.version}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: KombuTheme.accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Size: ${DownloadProgress.formatBytes(widget.release.apkSize)}',
          style: const TextStyle(color: KombuTheme.textDim, fontSize: 12),
        ),
        if ((widget.release.bodyNotes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: SingleChildScrollView(
              child: Text(
                widget.release.bodyNotes!.trim(),
                style: const TextStyle(
                    fontSize: 12, color: KombuTheme.textDim, height: 1.4),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Later'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Install'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloading(BuildContext context) {
    final p = _progress;
    final totalStr = p.total > 0 ? DownloadProgress.formatBytes(p.total) : '--';
    final receivedStr = DownloadProgress.formatBytes(p.received);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: const [
          Icon(Icons.downloading, color: KombuTheme.accent),
          SizedBox(width: 10),
          Text('Downloading update',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: p.total > 0 ? p.fraction : null,
            minHeight: 10,
            color: KombuTheme.accent,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$receivedStr / $totalStr',
                style: const TextStyle(fontSize: 12, color: KombuTheme.text)),
            Text(
              p.total > 0 ? '${(p.fraction * 100).toStringAsFixed(1)}%' : '--',
              style: const TextStyle(fontSize: 12, color: KombuTheme.accent),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.speed, size: 14, color: KombuTheme.textDim),
              const SizedBox(width: 4),
              Text(DownloadProgress.formatSpeed(p.bytesPerSec),
                  style: const TextStyle(
                      fontSize: 12, color: KombuTheme.textDim)),
            ]),
            Row(children: [
              const Icon(Icons.timer_outlined,
                  size: 14, color: KombuTheme.textDim),
              const SizedBox(width: 4),
              Text('ETA ${DownloadProgress.formatEta(p.eta)}',
                  style: const TextStyle(
                      fontSize: 12, color: KombuTheme.textDim)),
            ]),
          ],
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel'),
          ),
        ),
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: const [
          Icon(Icons.check_circle, color: KombuTheme.accent),
          SizedBox(width: 10),
          Text('Install ready',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        const Text(
          'Confirm the Android install prompt to finish updating. If it did not appear, allow "install unknown apps" for ScobySense in system settings and retry.',
          style: TextStyle(fontSize: 13, color: KombuTheme.textDim),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
      ],
    );
  }

  Widget _buildFailed(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: const [
          Icon(Icons.error_outline, color: KombuTheme.danger),
          SizedBox(width: 10),
          Text('Update failed',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Text(_error ?? 'Unknown error.',
            style: const TextStyle(fontSize: 13, color: KombuTheme.textDim)),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _start,
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
