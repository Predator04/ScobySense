import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'auth_service.dart';
import '../models/device.dart';

/// AppSync realtime (graphql-over-WS) subscription for device updates.
///
/// The realtime endpoint is the standard AppSync HTTP endpoint with the
/// `appsync-api` host swapped for `appsync-realtime-api`. Auth is passed as a
/// base64-encoded `header` query parameter on connect, then every subscription
/// start repeats the same auth block in its `extensions`.
///
/// Falls back silently (closes the socket) if auth is missing or the socket
/// drops — callers keep polling as a backstop.
class DeviceSubscriptionClient {
  final AuthService auth;
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Timer? _keepalive;
  Duration _keepaliveTimeout = const Duration(seconds: 30);
  String? _subId;
  bool _closed = false;
  int _backoffMs = 2000;

  final _controller = StreamController<BrewerDevice>.broadcast();
  Stream<BrewerDevice> get updates => _controller.stream;

  DeviceSubscriptionClient(this.auth);

  static const _realtimeHost =
      '46advo6mrng7znsfp6jzkkircy.appsync-realtime-api.us-east-1.amazonaws.com';
  static const _apiHost =
      '46advo6mrng7znsfp6jzkkircy.appsync-api.us-east-1.amazonaws.com';

  static const _onUpdateDevice = r'''
    subscription OnUpdateDevice {
      onUpdateDevice {
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
  ''';

  Future<void> start() async {
    _closed = false;
    await _connect();
  }

  Future<void> _connect() async {
    final tokens = await auth.currentTokens();
    if (tokens == null) {
      // No session yet — the caller is responsible for restarting after login.
      return;
    }
    final authHeaders = {
      'Authorization': tokens.idToken,
      'host': _apiHost,
    };
    final headerB64 = base64Url.encode(utf8.encode(jsonEncode(authHeaders)))
        .replaceAll('=', '');
    const payloadB64 = 'e30='; // base64('{}')
    final uri = Uri.parse(
        'wss://$_realtimeHost/graphql?header=$headerB64&payload=$payloadB64');

    try {
      _ch = IOWebSocketChannel.connect(
        uri,
        protocols: const ['graphql-ws'],
        pingInterval: const Duration(seconds: 20),
      );
    } catch (_) {
      _scheduleReconnect();
      return;
    }

    _ch!.sink.add(jsonEncode({'type': 'connection_init'}));
    _sub = _ch!.stream.listen(
      _onMessage,
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic>? msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = msg['type'];
    switch (type) {
      case 'connection_ack':
        final to = (msg['payload']?['connectionTimeoutMs'] as num?)?.toInt();
        if (to != null && to > 0) {
          _keepaliveTimeout = Duration(milliseconds: to);
        }
        _armKeepalive();
        _backoffMs = 2000;
        _startSubscription();
        break;
      case 'ka':
        _armKeepalive();
        break;
      case 'data':
        _handleData(msg);
        break;
      case 'error':
      case 'connection_error':
        _scheduleReconnect();
        break;
      case 'complete':
        break;
    }
  }

  void _armKeepalive() {
    _keepalive?.cancel();
    _keepalive = Timer(_keepaliveTimeout + const Duration(seconds: 5), () {
      _scheduleReconnect();
    });
  }

  Future<void> _startSubscription() async {
    final tokens = await auth.currentTokens();
    if (tokens == null) return;
    _subId = DateTime.now().microsecondsSinceEpoch.toString();
    final startMsg = {
      'id': _subId,
      'type': 'start',
      'payload': {
        'data': jsonEncode({'query': _onUpdateDevice, 'variables': {}}),
        'extensions': {
          'authorization': {
            'Authorization': tokens.idToken,
            'host': _apiHost,
          }
        }
      }
    };
    try {
      _ch?.sink.add(jsonEncode(startMsg));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _handleData(Map<String, dynamic> msg) {
    final data = msg['payload']?['data'];
    if (data is! Map) return;
    final devJson = data['onUpdateDevice'];
    if (devJson is! Map<String, dynamic>) return;
    try {
      _controller.add(BrewerDevice.fromJson(devJson));
    } catch (_) {}
  }

  void _scheduleReconnect() {
    _teardownSocket();
    if (_closed) return;
    _reconnectTimer?.cancel();
    final delay = _backoffMs;
    _backoffMs = (_backoffMs * 2).clamp(2000, 60000);
    _reconnectTimer =
        Timer(Duration(milliseconds: delay), () => _connect());
  }

  void _teardownSocket() {
    _keepalive?.cancel();
    _keepalive = null;
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    _subId = null;
  }

  Future<void> stop() async {
    _closed = true;
    _reconnectTimer?.cancel();
    _teardownSocket();
    await _controller.close();
  }
}
