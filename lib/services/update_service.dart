import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'install_apk.dart';
import 'errors.dart';

class ReleaseInfo {
  final String tag;
  final SemVer version;
  final String apkUrl;
  final String apkName;
  final int apkSize;
  final String? htmlUrl;
  final String? bodyNotes;

  ReleaseInfo({
    required this.tag,
    required this.version,
    required this.apkUrl,
    required this.apkName,
    required this.apkSize,
    this.htmlUrl,
    this.bodyNotes,
  });
}

class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;

  const SemVer(this.major, this.minor, this.patch);

  static SemVer parse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final core = s.split(RegExp('[-+]')).first;
    final parts = core.split('.');
    int part(int i) {
      if (parts.length <= i) return 0;
      return int.tryParse(parts[i]) ?? 0;
    }
    return SemVer(part(0), part(1), part(2));
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

class DownloadProgress {
  final int received;
  final int total;
  final double bytesPerSec;
  final Duration eta;

  const DownloadProgress({
    required this.received,
    required this.total,
    required this.bytesPerSec,
    required this.eta,
  });

  double get fraction => total == 0 ? 0 : (received / total).clamp(0.0, 1.0);

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String formatSpeed(double bps) {
    if (bps <= 0 || bps.isNaN || bps.isInfinite) return '--';
    if (bps < 1024) return '${bps.toStringAsFixed(0)} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  static String formatEta(Duration d) {
    if (d.inSeconds <= 0 || d.inSeconds > 24 * 3600) return '--';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class UpdateService {
  static const _repo = 'Predator04/ScobySense';
  static const _apiUrl =
      'https://api.github.com/repos/$_repo/releases/latest';

  final http.Client _client;
  bool _cancelled = false;

  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  Future<SemVer> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return SemVer.parse(info.version);
  }

  Future<PackageInfo> packageInfo() => PackageInfo.fromPlatform();

  Future<ReleaseInfo?> fetchLatest() async {
    http.Response resp;
    try {
      resp = await _client.get(
        Uri.parse(_apiUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'scobysense-app',
        },
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const NetworkFailure('Update check timed out.');
    } on SocketException catch (e) {
      throw NetworkFailure('Can\'t reach GitHub.', e);
    } catch (e) {
      throw classifyHttpError(e);
    }

    if (resp.statusCode == 404) {
      return null;
    }
    if (resp.statusCode >= 400) {
      throw ServerFailure('GitHub returned ${resp.statusCode}',
          statusCode: resp.statusCode);
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw UpdateFailure('Could not parse release info.', e);
    }

    final tag = (body['tag_name'] as String?) ?? '';
    if (tag.isEmpty) return null;
    final assets = (body['assets'] as List?) ?? const [];
    Map<String, dynamic>? apk;
    for (final a in assets) {
      if (a is Map<String, dynamic>) {
        final name = (a['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apk = a;
          break;
        }
      }
    }
    if (apk == null) {
      return null;
    }
    return ReleaseInfo(
      tag: tag,
      version: SemVer.parse(tag),
      apkUrl: (apk['browser_download_url'] as String?) ?? '',
      apkName: (apk['name'] as String?) ?? 'scobysense-update.apk',
      apkSize: (apk['size'] as num?)?.toInt() ?? 0,
      htmlUrl: body['html_url'] as String?,
      bodyNotes: body['body'] as String?,
    );
  }

  Future<ReleaseInfo?> checkForUpdate() async {
    final latest = await fetchLatest();
    if (latest == null) return null;
    final current = await currentVersion();
    if (latest.version.compareTo(current) > 0) {
      return latest;
    }
    return null;
  }

  void cancel() => _cancelled = true;

  Future<File> downloadApk(
    ReleaseInfo release, {
    required void Function(DownloadProgress) onProgress,
  }) async {
    _cancelled = false;
    final req = http.Request('GET', Uri.parse(release.apkUrl));
    req.headers['User-Agent'] = 'scobysense-app';
    http.StreamedResponse resp;
    try {
      resp = await _client.send(req).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const NetworkFailure('Download start timed out.');
    } on SocketException catch (e) {
      throw NetworkFailure('Can\'t reach the download server.', e);
    } catch (e) {
      throw classifyHttpError(e);
    }

    if (resp.statusCode >= 400) {
      throw ServerFailure('Download HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }

    final total = resp.contentLength ?? release.apkSize;
    final dir = await _apkDir();
    final file = File('${dir.path}/scobysense-update.apk');
    if (await file.exists()) {
      await file.delete();
    }
    final sink = file.openWrite();
    int received = 0;
    int lastReceived = 0;
    var lastTick = DateTime.now();
    double smoothedBps = 0;
    const alpha = 0.3;

    Timer? ticker;
    void emit() {
      final now = DateTime.now();
      final elapsed = now.difference(lastTick).inMilliseconds;
      if (elapsed <= 0) return;
      final bps = (received - lastReceived) * 1000 / elapsed;
      smoothedBps =
          smoothedBps == 0 ? bps : (alpha * bps + (1 - alpha) * smoothedBps);
      final remaining = (total - received).clamp(0, total);
      final etaSec = smoothedBps > 0 ? remaining / smoothedBps : 0;
      onProgress(DownloadProgress(
        received: received,
        total: total,
        bytesPerSec: smoothedBps,
        eta: Duration(milliseconds: (etaSec * 1000).round()),
      ));
      lastReceived = received;
      lastTick = now;
    }

    ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => emit());

    try {
      await for (final chunk in resp.stream) {
        if (_cancelled) {
          await sink.close();
          if (await file.exists()) await file.delete();
          throw const UpdateCancelled();
        }
        sink.add(chunk);
        received += chunk.length;
      }
      await sink.flush();
      await sink.close();
      ticker.cancel();
      onProgress(DownloadProgress(
        received: received,
        total: total == 0 ? received : total,
        bytesPerSec: 0,
        eta: Duration.zero,
      ));
      return file;
    } on UpdateCancelled {
      ticker.cancel();
      rethrow;
    } catch (e) {
      ticker.cancel();
      try {
        await sink.close();
      } catch (_) {}
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      throw UpdateFailure('Download failed: $e', e);
    }
  }

  Future<Directory> _apkDir() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  Future<void> installApk(File apk) async {
    await ApkInstaller.install(apk.path);
  }

  void dispose() {
    _client.close();
  }
}
