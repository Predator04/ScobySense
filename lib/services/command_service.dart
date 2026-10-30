import 'dart:math';
import 'appsync_client.dart';

final _deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

String commandTopic(String deviceId) {
  if (!_deviceIdPattern.hasMatch(deviceId)) {
    throw ArgumentError.value(deviceId, 'deviceId',
        'must match ^[A-Za-z0-9_-]+\$ (no "/", "..", "+", "#")');
  }
  return 'kombu/$deviceId/down/cmd';
}

int _cmdCounter = 0;
final _cmdRand = Random();
String _cmdId() {
  final ms = DateTime.now().millisecondsSinceEpoch;
  final n = (_cmdCounter = (_cmdCounter + 1) & 0xffff);
  final r = _cmdRand.nextInt(1 << 24).toRadixString(36);
  return 'scobysense-$ms-$n-$r';
}

class CommandService {
  final AppSyncClient client;
  CommandService(this.client);

  Future<bool> setBrewTimerSeconds(
      String deviceId, String side, int totalSeconds) {
    return client.pushCommand(commandTopic(deviceId), {
      'command': 'set_heater',
      'cmd_id': _cmdId(),
      'target': side,
      'params': {'remaining_time': totalSeconds},
    });
  }

  Future<bool> setBrewTimer(String deviceId, String side, int days) =>
      setBrewTimerSeconds(deviceId, side, days * 86400);

  Future<bool> stopBrew(String deviceId, String side) {
    return client.pushCommand(commandTopic(deviceId), {
      'command': 'set_heater',
      'cmd_id': _cmdId(),
      'target': side,
      'params': {'remaining_time': 0},
    });
  }

  // TODO: verify target-vs-params shape against the real device —
  // other commands put the toggle under params; set_sound currently uses target.
  Future<bool> setSound(String deviceId, bool on) {
    return client.pushCommand(commandTopic(deviceId), {
      'command': 'set_sound',
      'cmd_id': _cmdId(),
      'target': on ? 'on' : 'off',
    });
  }

  Future<bool> safetyStop(String deviceId) {
    return client.pushCommand(commandTopic(deviceId), {
      'command': 'set_stop_device',
      'cmd_id': _cmdId(),
    });
  }
}
