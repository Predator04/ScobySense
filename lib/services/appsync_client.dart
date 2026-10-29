import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../models/device.dart';

class AppSyncConfig {
  static const url =
      'https://46advo6mrng7znsfp6jzkkircy.appsync-api.us-east-1.amazonaws.com/graphql';
}

class GraphQLException implements Exception {
  final String message;
  GraphQLException(this.message);
  @override
  String toString() => 'GraphQLException: $message';
}

class AppSyncClient {
  final AuthService auth;
  AppSyncClient(this.auth);

  Future<Map<String, dynamic>> _post(String query,
      [Map<String, dynamic>? variables]) async {
    final tokens = await auth.currentTokens();
    if (tokens == null) throw GraphQLException('Not authenticated.');
    final body = <String, dynamic>{'query': query};
    if (variables != null) body['variables'] = variables;
    final resp = await http.post(
      Uri.parse(AppSyncConfig.url),
      headers: {
        'Authorization': tokens.idToken,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (resp.statusCode >= 400) {
      throw GraphQLException('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    if (decoded['errors'] != null) {
      throw GraphQLException(jsonEncode(decoded['errors']));
    }
    return (decoded['data'] as Map<String, dynamic>?) ?? const {};
  }

  static const _listDevices = r'''
    query ListDevices {
      listDevices(limit: 50) {
        items {
          id
          deviceId
          deviceName
          status
          f1Status
          f1Temp
          f1RemainingTime
          f2Status
          f2Temp
          f2RemainingTime
          temperatureUnit
          wifiConnected
          firmwareVersion
          lastSeen
          iotThingArn
        }
      }
    }
  ''';

  Future<List<BrewerDevice>> listDevices() async {
    final data = await _post(_listDevices);
    final items = ((data['listDevices'] as Map?)?['items'] as List?) ?? const [];
    return items
        .map((e) => BrewerDevice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static const _listAlerts = r'''
    query ListAlerts {
      listAlerts(limit: 50) {
        items { id message severity createdAt deviceId }
      }
    }
  ''';

  Future<List<Map<String, dynamic>>> listAlerts() async {
    final data = await _post(_listAlerts);
    final items = ((data['listAlerts'] as Map?)?['items'] as List?) ?? const [];
    return items.cast<Map<String, dynamic>>();
  }

  static const _brewCyclesByDevice = r'''
    query ByDevice($deviceId: ID!) {
      listBrewCycleEventByDevice(deviceId: $deviceId, limit: 50) {
        total
        activeF1 { id eventType side status timestamp expectedEndTime durationDays notes }
        activeF2 { id eventType side status timestamp expectedEndTime durationDays notes }
        batches {
          batchNumber
          isComplete
          f1 { id eventType side status timestamp expectedEndTime durationDays notes }
          f2 { id eventType side status timestamp expectedEndTime durationDays notes }
        }
      }
    }
  ''';

  Future<Map<String, dynamic>> brewCyclesByDevice(String deviceId) async {
    final data =
        await _post(_brewCyclesByDevice, {'deviceId': deviceId});
    return (data['listBrewCycleEventByDevice'] as Map<String, dynamic>?) ??
        const {};
  }

  static const _pushCommand = r'''
    mutation Push($topic: String!, $payload: AWSJSON!) {
      pushCommand(topic: $topic, payload: $payload)
    }
  ''';

  Future<String> pushCommand(String topic, Map<String, dynamic> payload) async {
    final data = await _post(_pushCommand, {
      'topic': topic,
      'payload': jsonEncode(payload),
    });
    return (data['pushCommand'] ?? '').toString();
  }
}
