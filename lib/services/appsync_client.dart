import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'errors.dart';
import '../models/device.dart';
import '../models/brew_cycle.dart';

class AppSyncConfig {
  static const url =
      'https://46advo6mrng7znsfp6jzkkircy.appsync-api.us-east-1.amazonaws.com/graphql';
}

class AppSyncClient {
  final AuthService auth;
  AppSyncClient(this.auth);

  Future<Map<String, dynamic>> _post(String query,
      [Map<String, dynamic>? variables]) async {
    final tokens = await auth.currentTokens();
    if (tokens == null) {
      throw const AuthFailure('Not signed in.');
    }
    final body = <String, dynamic>{'query': query};
    if (variables != null) body['variables'] = variables;

    http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse(AppSyncConfig.url),
            headers: {
              'Authorization': tokens.idToken,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const NetworkFailure('Server timed out.');
    } on SocketException catch (e) {
      throw NetworkFailure('Can\'t reach the server.', e);
    } catch (e) {
      throw classifyHttpError(e);
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw AuthFailure('Session rejected (${resp.statusCode}). Sign in again.');
    }
    if (resp.statusCode >= 500) {
      throw ServerFailure('Server error ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
    if (resp.statusCode >= 400) {
      throw ServerFailure('Request failed (${resp.statusCode}).',
          statusCode: resp.statusCode);
    }

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw ServerFailure('Bad response from server.', cause: e);
    }
    final errors = decoded['errors'];
    if (errors is List && errors.isNotEmpty) {
      final msg = errors
          .map((e) => (e is Map && e['message'] is String)
              ? e['message'] as String
              : e.toString())
          .join('; ');
      final lower = msg.toLowerCase();
      if (lower.contains('unauthorized') ||
          lower.contains('not authorized') ||
          lower.contains('token')) {
        throw AuthFailure(msg);
      }
      throw ServerFailure(msg);
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
    final items =
        ((data['listDevices'] as Map?)?['items'] as List?) ?? const [];
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

  static const _listAlertRules = r'''
    query ListAlertRules {
      listAlertRules(limit: 50) {
        items {
          id
          deviceId
          side
          metric
          comparator
          value
          enabled
          label
        }
      }
    }
  ''';

  Future<List<Map<String, dynamic>>> listAlertRules() async {
    try {
      final data = await _post(_listAlertRules);
      final items =
          ((data['listAlertRules'] as Map?)?['items'] as List?) ?? const [];
      return items.cast<Map<String, dynamic>>();
    } on ServerFailure {
      // Schema may not expose this field for every account; treat as empty.
      return const [];
    }
  }

  static const _updateBrewCycleEvent = r'''
    mutation UpdateBrew($input: UpdateBrewCycleEventInput!) {
      updateBrewCycleEvent(input: $input) { id notes }
    }
  ''';

  Future<Map<String, dynamic>> updateBrewCycleEventNotes(
      String id, String notes) async {
    final data = await _post(
      _updateBrewCycleEvent,
      {
        'input': {'id': id, 'notes': notes}
      },
    );
    return (data['updateBrewCycleEvent'] as Map<String, dynamic>?) ?? const {};
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
    final data = await _post(_brewCyclesByDevice, {'deviceId': deviceId});
    return (data['listBrewCycleEventByDevice'] as Map<String, dynamic>?) ??
        const {};
  }

  Future<BrewCycleReport> brewCycleReport(String deviceId) async {
    final raw = await brewCyclesByDevice(deviceId);
    return BrewCycleReport.fromJson(raw);
  }

  static const _pushCommand = r'''
    mutation Push($topic: String!, $payload: AWSJSON!) {
      pushCommand(topic: $topic, payload: $payload) {
        success
        topic
        messageId
        error
      }
    }
  ''';

  Future<bool> pushCommand(String topic, Map<String, dynamic> payload) async {
    final data = await _post(_pushCommand, {
      'topic': topic,
      'payload': jsonEncode(payload),
    });
    final result = (data['pushCommand'] as Map<String, dynamic>?) ?? const {};
    final success = result['success'] == true;
    if (!success) {
      final err = (result['error'] as String?)?.trim();
      throw ServerFailure(
        err != null && err.isNotEmpty ? err : 'Command rejected by cloud.',
      );
    }
    return true;
  }
}
