import 'package:shared_preferences/shared_preferences.dart';

/// App-wide shared prefs keys + light helpers.
class AppPrefs {
  static const kUnit = 'temperature_unit';
  static const kNotifications = 'notifications_enabled';
  static const kUse24Hour = 'use_24_hour_time';
  static const kScheduleF1Start = 'schedule_f1_start';
  static const kScheduleF1Stop = 'schedule_f1_stop';
  static const kScheduleF2Start = 'schedule_f2_start';
  static const kScheduleF2Stop = 'schedule_f2_stop';
  static const kTermsAccepted = 'terms_accepted_v1';

  static const int defaultF1Days = 3;
  static const int defaultF2Days = 7;

  static Future<String> unit() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kUnit) ?? 'F';
  }

  static Future<void> setUnit(String u) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kUnit, u);
  }

  static Future<bool> notifications() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kNotifications) ?? true;
  }

  static Future<void> setNotifications(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kNotifications, v);
  }

  static Future<bool> use24Hour() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kUse24Hour) ?? false;
  }

  static Future<void> setUse24Hour(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kUse24Hour, v);
  }

  static Future<bool> termsAccepted() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kTermsAccepted) ?? false;
  }

  static Future<void> setTermsAccepted(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kTermsAccepted, v);
  }

  static String _brewKey(String deviceId, String side) =>
      'brew:$deviceId:${side.toLowerCase()}days';

  static String _brewSecondsKey(String deviceId, String side) =>
      'brew:$deviceId:${side.toLowerCase()}seconds';

  static int defaultBrewDays(String side) =>
      side.toUpperCase() == 'F1' ? defaultF1Days : defaultF2Days;

  static int defaultBrewSeconds(String side) =>
      defaultBrewDays(side) * 86400;

  static Future<int> brewDays(String deviceId, String side) async {
    final s = await brewSeconds(deviceId, side);
    return s ~/ 86400;
  }

  static Future<void> setBrewDays(
      String deviceId, String side, int days) async {
    await setBrewSeconds(deviceId, side, days * 86400);
  }

  /// Reads total brew duration in seconds. Falls back to the legacy day-only
  /// key (pre-v0.5.8) so existing user settings survive the upgrade.
  static Future<int> brewSeconds(String deviceId, String side) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getInt(_brewSecondsKey(deviceId, side));
    if (s != null) return s;
    final legacyDays = p.getInt(_brewKey(deviceId, side));
    if (legacyDays != null) return legacyDays * 86400;
    return defaultBrewSeconds(side);
  }

  static Future<void> setBrewSeconds(
      String deviceId, String side, int totalSeconds) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_brewSecondsKey(deviceId, side), totalSeconds);
    await p.remove(_brewKey(deviceId, side));
  }

  static String _nameKey(String deviceId) => 'device:$deviceId:name';

  static Future<String?> deviceDisplayName(String deviceId) async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_nameKey(deviceId));
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> setDeviceDisplayName(
      String deviceId, String? name) async {
    final p = await SharedPreferences.getInstance();
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await p.remove(_nameKey(deviceId));
    } else {
      await p.setString(_nameKey(deviceId), trimmed);
    }
  }

  static Future<Map<String, String>> loadDeviceDisplayNames() async {
    final p = await SharedPreferences.getInstance();
    final out = <String, String>{};
    for (final k in p.getKeys()) {
      if (!k.startsWith('device:') || !k.endsWith(':name')) continue;
      final id = k.substring('device:'.length, k.length - ':name'.length);
      final v = p.getString(k);
      if (v != null && v.isNotEmpty) out[id] = v;
    }
    return out;
  }
}

/// Device raw temps are reported in Fahrenheit despite `temperatureUnit: "C"`.
/// Everything in the app should go through [formatTemp] so a single switch
/// in Settings flips the whole UI.
String formatTemp(double? rawFahrenheit, String unit, {int fractionDigits = 1}) {
  if (rawFahrenheit == null) return '--';
  final v = unit == 'C' ? (rawFahrenheit - 32.0) * 5.0 / 9.0 : rawFahrenheit;
  return '${v.toStringAsFixed(fractionDigits)}°$unit';
}

double? convertTemp(double? rawFahrenheit, String unit) {
  if (rawFahrenheit == null) return null;
  return unit == 'C' ? (rawFahrenheit - 32.0) * 5.0 / 9.0 : rawFahrenheit;
}
