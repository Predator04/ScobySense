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

  factory TempSample.fromJson(Map<String, dynamic> j) => TempSample(
        ts: (j['ts'] as num).toInt(),
        f1Temp: (j['f1Temp'] as num?)?.toDouble(),
        f2Temp: (j['f2Temp'] as num?)?.toDouble(),
        f1Status: j['f1Status'] as String?,
        f2Status: j['f2Status'] as String?,
      );
}

class HistoryStore {
  static const _cap = 2000;
  static String _key(String deviceId) => 'history:$deviceId';

  Future<List<TempSample>> load(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(deviceId));
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(TempSample.fromJson).toList();
  }

  Future<void> append(String deviceId, TempSample sample) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await load(deviceId);
    existing.add(sample);
    final trimmed =
        existing.length > _cap ? existing.sublist(existing.length - _cap) : existing;
    await prefs.setString(
      _key(deviceId),
      jsonEncode(trimmed.map((s) => s.toJson()).toList()),
    );
  }
}
