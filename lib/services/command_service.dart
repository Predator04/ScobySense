import 'appsync_client.dart';

// -----------------------------------------------------------------------------
// PAYLOAD_WRAPPER_TODO
//
// The exact JSON wrapper the device expects for pushCommand is NOT confirmed.
// Known from reverse-engineering libapp.so:
//   topic = "<deviceId>/down/cmd"
//   commands = set_heater, set_sound, safety_stop, set_heating_time
//   device ACKs with "start ack message received for ..."
//
// The default wrapper below matches the obvious shape ({command, value}),
// but DO NOT trust it until confirmed by a live packet capture against the
// real device. Flip the wrapper here in one place when the real shape is known.
// -----------------------------------------------------------------------------
Map<String, dynamic> buildCommandPayload(String command, Object? value) {
  // PAYLOAD_WRAPPER_TODO — confirm this shape before relying on writes.
  return {'command': command, if (value != null) 'value': value};
}

String commandTopic(String deviceId) => '$deviceId/down/cmd';

class CommandService {
  final AppSyncClient client;
  CommandService(this.client);

  Future<String> _send(String deviceId, String command, Object? value) {
    return client.pushCommand(
      commandTopic(deviceId),
      buildCommandPayload(command, value),
    );
  }

  Future<String> setHeaterF1(String deviceId, bool on) =>
      _send(deviceId, 'set_heater', {'side': 'F1', 'on': on});

  Future<String> setHeaterF2(String deviceId, bool on) =>
      _send(deviceId, 'set_heater', {'side': 'F2', 'on': on});

  Future<String> setBrewTimer(String deviceId, String side, int days) =>
      _send(deviceId, 'set_heating_time', {'side': side, 'durationDays': days});

  Future<String> setSound(String deviceId, bool on) =>
      _send(deviceId, 'set_sound', on);

  Future<String> safetyStop(String deviceId) =>
      _send(deviceId, 'safety_stop', true);
}
