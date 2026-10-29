import 'package:shared_preferences/shared_preferences.dart';

/// App-wide shared prefs keys + light helpers.
class AppPrefs {
  static const kUnit = 'temperature_unit';
  static const kNotifications = 'notifications_enabled';
  static const kScheduleF1Start = 'schedule_f1_start';
  static const kScheduleF1Stop = 'schedule_f1_stop';
  static const kScheduleF2Start = 'schedule_f2_start';
  static const kScheduleF2Stop = 'schedule_f2_stop';

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
