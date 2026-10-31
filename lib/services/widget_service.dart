import 'package:home_widget/home_widget.dart';
import '../models/device.dart';
import '../utils/time_format.dart';
import 'prefs.dart';

class WidgetService {
  WidgetService._();
  static final WidgetService instance = WidgetService._();

  // Must match the Kotlin class name of ScobySenseWidgetProvider so home_widget
  // can resolve the AppWidgetManager via Android's component resolver.
  static const _providerName = 'ScobySenseWidgetProvider';

  Future<void> publish(BrewerDevice d) async {
    final unit = await AppPrefs.unit();
    final use24 = await AppPrefs.use24Hour();

    final name =
        (d.deviceName != null && d.deviceName!.isNotEmpty)
            ? d.deviceName!
            : d.deviceId;
    final f1 = _formatSide('F1', d.f1On, d.f1Temp, d.f1RemainingTime, unit);
    final f2 = _formatSide('F2', d.f2On, d.f2Temp, d.f2RemainingTime, unit);
    final updated = 'Updated ${appTimeOfDayFormat(use24).format(DateTime.now())}';

    await HomeWidget.saveWidgetData<String>('name', name);
    await HomeWidget.saveWidgetData<String>('f1', f1);
    await HomeWidget.saveWidgetData<String>('f2', f2);
    await HomeWidget.saveWidgetData<String>('updated', updated);
    await HomeWidget.updateWidget(
      name: _providerName,
      androidName: _providerName,
    );
  }

  String _formatSide(
    String side,
    bool on,
    double? rawTemp,
    String? iso,
    String unit,
  ) {
    final temp = formatTemp(rawTemp, unit);
    if (!on) return '$side  $temp  ·  off';
    final remaining = _formatRemaining(iso);
    return '$side  $temp  ·  $remaining';
  }

  String _formatRemaining(String? iso) {
    if (iso == null || iso.isEmpty) return 'heating';
    final end = DateTime.tryParse(iso)?.toLocal();
    if (end == null) return 'heating';
    final diff = end.difference(DateTime.now());
    if (diff.isNegative || diff == Duration.zero) return 'done';
    if (diff.inDays >= 1) {
      final h = diff.inHours.remainder(24);
      return '${diff.inDays}d ${h}h left';
    }
    if (diff.inHours >= 1) {
      final m = diff.inMinutes.remainder(60);
      return '${diff.inHours}h ${m}m left';
    }
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m left';
    return '<1m left';
  }
}
