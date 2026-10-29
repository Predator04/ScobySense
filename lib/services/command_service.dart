import 'appsync_client.dart';

String commandTopic(String deviceId) => 'kombu/$deviceId/down/cmd';

String _cmdId() => 'scobysense-${DateTime.now().millisecondsSinceEpoch}';

class CommandService {
  final AppSyncClient client;
  CommandService(this.client);

  Future<bool> setBrewTimer(String deviceId, String side, int days) {
    return client.pushCommand(commandTopic(deviceId), {
      'command': 'set_heater',
      'cmd_id': _cmdId(),
      'target': side,
      'params': {'remaining_time': days * 86400},
    });
  }

  Future<bool> stopBrew(String deviceId, String side) {
    return client.pushCommand(commandTopic(deviceId), {
      'command': 'set_heater',
      'cmd_id': _cmdId(),
      'target': side,
      'params': {'remaining_time': 0},
    });
  }

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
