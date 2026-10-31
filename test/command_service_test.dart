import 'package:flutter_test/flutter_test.dart';
import 'package:scobysense/services/appsync_client.dart';
import 'package:scobysense/services/auth_service.dart';
import 'package:scobysense/services/command_service.dart';

class _FakeAppSync extends AppSyncClient {
  _FakeAppSync() : super(AuthService());
  final topics = <String>[];
  final payloads = <Map<String, dynamic>>[];

  @override
  Future<bool> pushCommand(String topic, Map<String, dynamic> payload) async {
    topics.add(topic);
    payloads.add(payload);
    return true;
  }
}

void main() {
  group('commandTopic', () {
    test('accepts A-Za-z0-9_- device ids', () {
      expect(commandTopic('abc'), 'kombu/abc/down/cmd');
      expect(commandTopic('Dev_01-A'), 'kombu/Dev_01-A/down/cmd');
      expect(commandTopic('XYZ'), 'kombu/XYZ/down/cmd');
    });

    test('rejects "/", "..", "+", "#" and other MQTT metachars', () {
      for (final bad in ['a/b', '..', 'a..b', 'a+b', 'a#b', 'a b', 'a/#', 'a/+', '', 'a.b']) {
        expect(() => commandTopic(bad), throwsA(isA<ArgumentError>()),
            reason: 'should reject: "$bad"');
      }
    });
  });

  group('CommandService', () {
    test('setBrewTimerSeconds sends set_heater with cmd_id, target, remaining_time', () async {
      final fake = _FakeAppSync();
      final svc = CommandService(fake);

      final ok = await svc.setBrewTimerSeconds('dev1', 'f1', 3600);
      expect(ok, true);
      expect(fake.topics.single, 'kombu/dev1/down/cmd');

      final payload = fake.payloads.single;
      expect(payload['command'], 'set_heater');
      expect(payload['target'], 'f1');
      expect(payload['cmd_id'], isA<String>());
      expect((payload['cmd_id'] as String).startsWith('scobysense-'), true);
      final params = payload['params'] as Map<String, dynamic>;
      expect(params['remaining_time'], 3600);
    });

    test('setBrewTimer multiplies days by 86400', () async {
      final fake = _FakeAppSync();
      await CommandService(fake).setBrewTimer('d', 'f2', 7);
      expect(
        (fake.payloads.single['params'] as Map)['remaining_time'],
        7 * 86400,
      );
    });

    test('stopBrew sends remaining_time=0', () async {
      final fake = _FakeAppSync();
      await CommandService(fake).stopBrew('d', 'f1');
      final p = fake.payloads.single;
      expect(p['command'], 'set_heater');
      expect((p['params'] as Map)['remaining_time'], 0);
    });

    test('generates unique cmd_id even when called in a tight loop', () async {
      final fake = _FakeAppSync();
      final svc = CommandService(fake);
      for (var i = 0; i < 100; i++) {
        await svc.setBrewTimerSeconds('d', 'f1', i);
      }
      final ids = fake.payloads.map((p) => p['cmd_id'] as String).toSet();
      expect(ids.length, 100, reason: 'all cmd_ids must be distinct');
    });

    test('rejects invalid deviceId before touching the client', () async {
      final fake = _FakeAppSync();
      final svc = CommandService(fake);
      expect(
        () => svc.setBrewTimerSeconds('bad/id', 'f1', 10),
        throwsA(isA<ArgumentError>()),
      );
      expect(fake.payloads, isEmpty);
    });
  });
}
