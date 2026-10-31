import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';

/// Per-device snapshot of the last successfully-seen device state. Used to
/// render a meaningful UI when the network is down or the first load fails,
/// instead of a blank spinner.
class StateCache {
  StateCache._();
  static final StateCache instance = StateCache._();

  static const _listKey = 'state_cache:devices_v1';
  static String _snapKey(String deviceId) => 'state_cache:device:$deviceId';

  Future<void> saveDevices(List<BrewerDevice> devices) async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc().toIso8601String();
    final list = devices.map((d) => _encode(d, now)).toList();
    await p.setString(_listKey, jsonEncode({'ts': now, 'devices': list}));
    for (final d in devices) {
      await p.setString(_snapKey(d.deviceId), jsonEncode(_encode(d, now)));
    }
  }

  Future<CachedDevices?> loadDevices() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_listKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final ts = DateTime.tryParse(j['ts']?.toString() ?? '');
      final listRaw = j['devices'];
      if (listRaw is! List) return null;
      final devices = <BrewerDevice>[];
      for (final e in listRaw) {
        if (e is Map<String, dynamic>) {
          devices.add(BrewerDevice.fromJson(e));
        }
      }
      return CachedDevices(devices: devices, savedAt: ts);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDevice(BrewerDevice d) async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc().toIso8601String();
    await p.setString(_snapKey(d.deviceId), jsonEncode(_encode(d, now)));
  }

  Future<CachedDevice?> loadDevice(String deviceId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_snapKey(deviceId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final ts = DateTime.tryParse(j['_savedAt']?.toString() ?? '');
      return CachedDevice(device: BrewerDevice.fromJson(j), savedAt: ts);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _encode(BrewerDevice d, String savedAt) => {
        'id': d.id,
        'deviceId': d.deviceId,
        'deviceName': d.deviceName,
        'status': d.status,
        'f1Status': d.f1Status,
        'f1Temp': d.f1Temp,
        'f1RemainingTime': d.f1RemainingTime,
        'f2Status': d.f2Status,
        'f2Temp': d.f2Temp,
        'f2RemainingTime': d.f2RemainingTime,
        'temperatureUnit': d.temperatureUnit,
        'wifiConnected': d.wifiConnected,
        'firmwareVersion': d.firmwareVersion,
        'lastSeen': d.lastSeen,
        'iotThingArn': d.iotThingArn,
        '_savedAt': savedAt,
      };
}

class CachedDevices {
  final List<BrewerDevice> devices;
  final DateTime? savedAt;
  CachedDevices({required this.devices, required this.savedAt});
}

class CachedDevice {
  final BrewerDevice device;
  final DateTime? savedAt;
  CachedDevice({required this.device, required this.savedAt});
}

String formatStaleness(DateTime? savedAtUtc) {
  if (savedAtUtc == null) return 'cached';
  final diff = DateTime.now().toUtc().difference(savedAtUtc);
  if (diff.inSeconds < 60) return 'as of just now';
  if (diff.inMinutes < 60) return 'as of ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'as of ${diff.inHours}h ago';
  return 'as of ${diff.inDays}d ago';
}
