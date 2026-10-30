import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TempSample {
  final int ts;
  final double? f1Temp;
  final double? f2Temp;
  final String? f1Status;
  final String? f2Status;
  TempSample({
    required this.ts,
    this.f1Temp,
    this.f2Temp,
    this.f1Status,
    this.f2Status,
  });

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'f1Temp': f1Temp,
        'f2Temp': f2Temp,
        'f1Status': f1Status,
        'f2Status': f2Status,
      };

  /// Returns null if the entry is unusable (missing/invalid `ts`). Callers
  /// filter nulls out so one bad record can't poison the whole load.
  static TempSample? tryFromJson(Map<String, dynamic> j) {
    final rawTs = j['ts'];
    if (rawTs is! num) return null;
    return TempSample(
      ts: rawTs.toInt(),
      f1Temp: (j['f1Temp'] as num?)?.toDouble(),
      f2Temp: (j['f2Temp'] as num?)?.toDouble(),
      f1Status: j['f1Status'] as String?,
      f2Status: j['f2Status'] as String?,
    );
  }
}

class HistoryStore {
  static const _cap = 2000;
  static String _key(String deviceId) => 'history:$deviceId';

  // Per-device write chain so concurrent appends (poll + live push) don't
  // read-modify-write the same slot and lose samples.
  final Map<String, Future<void>> _pending = {};

  Future<List<TempSample>> load(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(deviceId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <TempSample>[];
      for (final e in decoded) {
        if (e is Map<String, dynamic>) {
          final s = TempSample.tryFromJson(e);
          if (s != null) out.add(s);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> append(String deviceId, TempSample sample) {
    final prev = _pending[deviceId] ?? Future<void>.value();
    final next = prev.then((_) => _doAppend(deviceId, sample))
        .catchError((_) {});
    _pending[deviceId] = next;
    return next;
  }

  Future<void> _doAppend(String deviceId, TempSample sample) async {
    final prefs = await SharedPreferences.getInstance();
    List<TempSample> existing;
    try {
      existing = await load(deviceId);
    } catch (_) {
      existing = <TempSample>[];
    }
    existing.add(sample);
    final trimmed =
        existing.length > _cap ? existing.sublist(existing.length - _cap) : existing;
    await prefs.setString(
      _key(deviceId),
      jsonEncode(trimmed.map((s) => s.toJson()).toList()),
    );
  }
}
