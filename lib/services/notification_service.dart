import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/device.dart';
import 'prefs.dart';

/// Signature for the action callback. Returns a human-friendly success/failure
/// message that is then shown as a tiny follow-up notification.
typedef NotificationActionHandler = Future<String> Function(
    String deviceId, String side, String action);

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

  NotificationActionHandler? _actionHandler;

  /// Register a callback that executes a notification action. Called from
  /// main.dart once auth/CommandService are wired up.
  void setActionHandler(NotificationActionHandler handler) {
    _actionHandler = handler;
  }

  Future<void> init() async {
    if (_ready) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onResponse,
    );
    try {
      final android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {}
    _ready = true;
  }

  Future<bool> get enabled => AppPrefs.notifications();

  void _onResponse(NotificationResponse resp) {
    // Payload shape: "action|deviceId|side"
    final payload = resp.payload;
    final actionId = resp.actionId;
    if (payload == null || payload.isEmpty) return;
    final parts = payload.split('|');
    if (parts.length < 3) return;
    final deviceId = parts[1];
    final side = parts[2];
    // actionId is null when the user taps the body — ignore in that case.
    if (actionId == null || actionId.isEmpty) return;
    final handler = _actionHandler;
    if (handler == null) return;
    // Fire and forget — show a confirmation notification when it resolves.
    () async {
      try {
        final msg = await handler(deviceId, side, actionId);
        await _showPlain(
          'ScobySense',
          msg,
          id: 300 + (Object.hash(deviceId, side, actionId) & 0x7fff),
        );
      } catch (e) {
        await _showPlain(
          'ScobySense',
          'Action failed: $e',
          id: 300 + (Object.hash(deviceId, side, actionId, 'err') & 0x7fff),
        );
      }
    }();
  }

  Future<void> _showPlain(String title, String body,
      {int id = 1}) async {
    if (!_ready) return;
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

  Future<void> _show(
    String tag,
    String title,
    String body, {
    int id = 1,
    List<AndroidNotificationAction>? actions,
    String? payload,
  }) async {
    if (!_ready) return;
    if (!await enabled) return;
    final now = DateTime.now();
    final last = _lastFired[tag];
    if (last != null && now.difference(last) < const Duration(minutes: 10)) {
      // Debounce the same alert for 10 minutes to avoid spamming.
      return;
    }
    _lastFired[tag] = now;
    final android = AndroidNotificationDetails(
      'scobysense_default',
      'ScobySense',
      channelDescription: 'Brew-timer completions and threshold alerts.',
      importance: Importance.high,
      priority: Priority.high,
      actions: actions,
    );
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: android),
      payload: payload,
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
      final actions = (side == 'F1' || side == 'F2')
          ? <AndroidNotificationAction>[
              AndroidNotificationAction('stop', 'Turn off',
                  showsUserInterface: false, cancelNotification: true),
            ]
          : null;
      await _show(
        tag,
        'ScobySense alert',
        '$label — current ${actual.toStringAsFixed(1)}°F',
        id: 100 + tag.hashCode.abs() % 1000,
        actions: actions,
        payload: 'alert|${device.deviceId}|${side ?? ''}',
      );
    }
  }

  /// Fire a one-shot notification when a brew timer completes (the
  /// `*RemainingTime` ISO timestamp has just passed).
  Future<void> brewTimerDone(BrewerDevice device, String side) async {
    final tag = 'timer:${device.deviceId}:$side';
    // Fold deviceId into the notification id so device B's F1-done doesn't
    // replace device A's open notification. (Android IDs are 32-bit signed.)
    final composite = Object.hash(device.deviceId, side) & 0x7fffffff;
    await _show(
      tag,
      'Brew timer done',
      '${device.deviceName ?? device.deviceId} — $side cycle complete.',
      id: 200 + (composite % 100000),
      actions: const [
        AndroidNotificationAction('stop', 'Turn off',
            showsUserInterface: false, cancelNotification: true),
        AndroidNotificationAction('add_day', 'Add 1 day',
            showsUserInterface: false, cancelNotification: true),
      ],
      payload: 'done|${device.deviceId}|$side',
    );
  }
}
