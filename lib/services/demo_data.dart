import '../models/brew_cycle.dart';
import '../models/device.dart';
import 'history_store.dart';

class DemoData {
  static const String deviceId = 'demo-0001';
  static const String deviceName = 'Demo Brewer';

  static BrewerDevice device() {
    final now = DateTime.now().toUtc();
    final f2End = now.add(const Duration(days: 3, hours: 2));
    return BrewerDevice(
      id: deviceId,
      deviceId: deviceId,
      deviceName: deviceName,
      status: 'online',
      f1Status: 'off',
      f1Temp: 27.0,
      f1RemainingTime: '',
      f2Status: 'on',
      f2Temp: 28.0,
      f2RemainingTime: f2End.toIso8601String(),
      temperatureUnit: 'C',
      wifiConnected: true,
      firmwareVersion: '1.4.2-demo',
      lastSeen: now.toIso8601String(),
      iotThingArn: 'arn:aws:iot:us-east-1:000000000000:thing/demo-0001',
    );
  }

  static List<BrewerDevice> listDevices() => [device()];

  static List<TempSample> history() {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final out = <TempSample>[];
    for (int i = 59; i >= 0; i--) {
      final t = nowSec - i * 60;
      final f1 = 26.6 + ((i % 7) - 3) * 0.08;
      final f2 = 27.8 + ((i % 5) - 2) * 0.07;
      out.add(TempSample(
        ts: t,
        f1Temp: double.parse(f1.toStringAsFixed(2)),
        f2Temp: double.parse(f2.toStringAsFixed(2)),
        f1Status: 'off',
        f2Status: 'on',
      ));
    }
    return out;
  }

  static BrewCycleReport brewCycleReport() {
    final now = DateTime.now().toUtc();
    final f1Start = now.subtract(const Duration(days: 9));
    final f1End = now.subtract(const Duration(days: 2));
    final f2Start = now.subtract(const Duration(days: 1));
    final f2End = now.add(const Duration(days: 3, hours: 2));
    final activeF2 = BrewStage(
      id: 'demo-stage-f2-active',
      eventType: 'brew',
      side: 'F2',
      status: 'running',
      timestamp: f2Start.toIso8601String(),
      expectedEndTime: f2End.toIso8601String(),
      durationDays: 4,
      notes: 'Second ferment — ginger + lemon.',
    );
    final completedF1 = BrewStage(
      id: 'demo-stage-f1-done',
      eventType: 'brew',
      side: 'F1',
      status: 'complete',
      timestamp: f1Start.toIso8601String(),
      expectedEndTime: f1End.toIso8601String(),
      durationDays: 7,
      notes: 'First ferment — green tea starter.',
    );
    return BrewCycleReport(
      total: 1,
      activeF1: null,
      activeF2: activeF2,
      batches: [
        BrewBatch(
          batchNumber: 1,
          isComplete: false,
          f1: completedF1,
          f2: activeF2,
        ),
      ],
    );
  }
}
