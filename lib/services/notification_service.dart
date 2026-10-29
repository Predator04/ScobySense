import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/device.dart';
import 'prefs.dart';

/// Local notifications wrapper.
///
/// All deliveries happen on-device while the app is alive. The server-side
/// push system used by the official app (Firebase Cloud Messaging) is
/// intentionally out of scope.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  final Map<String, DateTime> _lastFired = {};

  Future<void> init() async {
    if (_ready) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);
    try {
      final android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {}
    _ready = true;
  }

  Future<bool> get enabled => AppPrefs.notifications();

  Future<void> _show(String tag, String title, String body,
      {int id = 1}) async {
    if (!_ready) return;
    if (!await enabled) return;
    final now = DateTime.now();
    final last = _lastFired[tag];
    if (last != null && now.difference(last) < const Duration(minutes: 10)) {
      // Debounce the same alert for 10 minutes to avoid spamming.
      return;
    }
    _lastFired[tag] = now;
    const android = AndroidNotificationDetails(
      'scobysense_default',
      'ScobySense',
      channelDescription: 'Brew-timer completions and threshold alerts.',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: android),
    );
  }

  /// Evaluate [device] against user-defined [rules] and fire notifications
  /// when a numeric threshold is crossed. Each rule has shape:
  /// `{side: F1|F2, metric: temperature|time, comparator: gt|lt|eq,
  ///   value: double, enabled: bool, label: String?}`.
  Future<void> evaluate(BrewerDevice device,
      {required List<Map<String, dynamic>> rules}) async {
    if (!await enabled) return;
    for (final r in rules) {
      final enabled = r['enabled'];
      if (enabled is bool && !enabled) continue;
      final deviceFilter = r['deviceId'] as String?;
      if (deviceFilter != null &&
          deviceFilter.isNotEmpty &&
          deviceFilter != device.deviceId) {
        continue;
      }
      final side = (r['side'] as String?)?.toUpperCase();
      final metric = (r['metric'] as String?)?.toLowerCase() ?? 'temperature';
      final comparator = (r['comparator'] as String?)?.toLowerCase() ?? 'gt';
      final value = (r['value'] as num?)?.toDouble();
      if (value == null) continue;

      double? actual;
      if (metric == 'temperature') {
        actual = side == 'F2' ? device.f2Temp : device.f1Temp;
      }
      if (actual == null) continue;

      bool trips;
      switch (comparator) {
        case 'lt':
          trips = actual < value;
          break;
        case 'eq':
          trips = (actual - value).abs() < 0.5;
          break;
        default:
          trips = actual > value;
      }
      if (!trips) continue;

      final label = (r['label'] as String?) ??
          '${side ?? 'F?'} $metric $comparator $value';
      final tag = '${r['id']}';
      await _show(
        tag,
        'ScobySense alert',
        '$label — current ${actual.toStringAsFixed(1)}°F',
        id: 100 + tag.hashCode.abs() % 1000,
      );
    }
  }

  /// Fire a one-shot notification when a brew timer completes (the
  /// `*RemainingTime` ISO timestamp has just passed).
  Future<void> brewTimerDone(BrewerDevice device, String side) async {
    final tag = 'timer:${device.deviceId}:$side';
    await _show(
      tag,
      'Brew timer done',
      '${device.deviceName ?? device.deviceId} — $side cycle complete.',
      id: 200 + side.hashCode.abs() % 100,
    );
  }
}
