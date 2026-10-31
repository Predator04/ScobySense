import 'package:flutter_test/flutter_test.dart';
import 'package:scobysense/models/device.dart';

void main() {
  group('BrewerDevice.fromJson', () {
    test('parses a representative appsync payload', () {
      final json = <String, dynamic>{
        'id': 'dev-xyz',
        'deviceId': 'dev-xyz',
        'deviceName': 'Kitchen',
        'status': 'online',
        'f1Status': 'on',
        'f1Temp': 24.5,
        'f1RemainingTime': '3600',
        'f2Status': 'off',
        'f2Temp': 20.0,
        'f2RemainingTime': '0',
        'temperatureUnit': 'C',
        'wifiConnected': null, // field present but null → stays null
        'firmwareVersion': '1.2.3',
        'lastSeen': '2026-10-30T00:00:00Z',
        'iotThingArn': 'arn:aws:iot:x',
      };

      final d = BrewerDevice.fromJson(json);
      expect(d.id, 'dev-xyz');
      expect(d.deviceId, 'dev-xyz');
      expect(d.deviceName, 'Kitchen');
      expect(d.status, 'online');
      expect(d.f1Temp, 24.5);
      expect(d.f2Temp, 20.0);
      expect(d.f1RemainingTime, '3600');
      expect(d.wifiConnected, isNull);
      expect(d.f1On, true);
      expect(d.f2On, false);
    });

    test('null numeric temps stay null; missing fields default to null', () {
      final d = BrewerDevice.fromJson({
        'id': 'd',
        'deviceId': 'd',
        'f1Temp': null,
      });
      expect(d.f1Temp, isNull);
      expect(d.f2Temp, isNull);
      expect(d.deviceName, isNull);
      expect(d.wifiConnected, isNull);
      expect(d.f1On, false);
      expect(d.f2On, false);
    });

    test('numeric temps given as int are coerced to double', () {
      final d = BrewerDevice.fromJson({
        'id': 'd',
        'deviceId': 'd',
        'f1Temp': 22, // int in JSON
      });
      expect(d.f1Temp, 22.0);
    });

    test('id falls back to deviceId when id is absent', () {
      final d = BrewerDevice.fromJson({'deviceId': 'only-device-id'});
      expect(d.id, 'only-device-id');
      expect(d.deviceId, 'only-device-id');
    });
  });
}
