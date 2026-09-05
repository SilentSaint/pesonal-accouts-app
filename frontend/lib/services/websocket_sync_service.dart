import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';
import 'auth_service.dart';

enum SyncConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class SyncEvent {
  const SyncEvent({
    required this.type,
    required this.entityId,
    required this.payload,
    required this.occurredAt,
  });

  final String type;
  final String entityId;
  final Map<String, dynamic> payload;
  final DateTime occurredAt;

  static SyncEvent? tryParse(Object? message) {
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is! Map || decoded['version'] != 1) return null;
      final type = decoded['type'];
      final entityId = decoded['entityId'];
      final payload = decoded['payload'];
      final occurredAt = decoded['occurredAt'];
      if (type is! String ||
          entityId is! String ||
          payload is! Map ||
          occurredAt is! String) {
        return null;
      }
      return SyncEvent(
        type: type,
        entityId: entityId,
        payload: Map<String, dynamic>.from(payload),
        occurredAt: DateTime.parse(occurredAt),
      );
    } catch (_) {
      return null;
    }
  }
}

abstract interface class SyncSocket {
  Stream<Object?> get stream;
  Future<void> close();
}

class _ChannelSyncSocket implements SyncSocket {
  _ChannelSyncSocket(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<Object?> get stream => _channel.stream;

  @override
  Future<void> close() => _channel.sink.close();
}

typedef SyncSocketConnector = Future<SyncSocket> Function(Uri uri);

class WebSocketSyncService extends ChangeNotifier {
  static final WebSocketSyncService _instance =
      WebSocketSyncService._internal();

  factory WebSocketSyncService() => _instance;

  WebSocketSyncService._internal()
      : _endpointProvider = (() => ApiConfig.websocketUrl),
        _tokenProvider = (() => AuthService().backendAuthorizationToken),
        _connector = _connectChannel,
        _reconnectDelay = null;

  WebSocketSyncService.forTesting({
    required String Function() endpointProvider,
    required String? Function() tokenProvider,
    required SyncSocketConnector connector,
    void Function(Duration)? reconnectDelay,
  })  : _endpointProvider = endpointProvider,
        _tokenProvider = tokenProvider,
        _connector = connector,
        _reconnectDelay = reconnectDelay;

  static Future<SyncSocket> _connectChannel(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return _ChannelSyncSocket(channel);
  }

  final String Function() _endpointProvider;
  final String? Function() _tokenProvider;
  final SyncSocketConnector _connector;
  final void Function(Duration)? _reconnectDelay;

  SyncConnectionState _state = SyncConnectionState.disconnected;
  SyncConnectionState get state => _state;
  bool get isConnected => _state == SyncConnectionState.connected;

  DateTime? _lastSyncTimestamp;
  DateTime? get lastSyncTimestamp => _lastSyncTimestamp;
  String? _lastError;
  String? get lastError => _lastError;

  StreamSubscription<Object?>? _messages;
  SyncSocket? _socket;
  Timer? _retryTimer;
  bool _manuallyDisconnected = false;
  int _reconnectAttempt = 0;

  void Function(SyncEvent event)? onSyncEvent;
  Future<void> Function()? onReconnected;

  Future<void> connect() async {
    if (_state == SyncConnectionState.connected ||
        _state == SyncConnectionState.connecting) {
      return;
    }
    _manuallyDisconnected = false;
    _retryTimer?.cancel();
    _retryTimer = null;

    final endpoint = _endpointProvider();
    final token = _tokenProvider();
    if (endpoint.isEmpty || token == null || token.isEmpty) {
      _state = SyncConnectionState.disconnected;
      _lastError = endpoint.isEmpty
          ? 'Live sync is not configured.'
          : 'Sign in to enable live sync.';
      notifyListeners();
      return;
    }

    _state = SyncConnectionState.connecting;
    notifyListeners();
    try {
      final endpointUri = Uri.parse(endpoint);
      final uri = endpointUri.replace(
        queryParameters: {
          ...endpointUri.queryParameters,
          'token': token,
        },
      );
      final socket = await _connector(uri);
      if (_manuallyDisconnected) {
        await socket.close();
        return;
      }

      _socket = socket;
      _messages = socket.stream.listen(
        _handleMessage,
        onError: _handleConnectionFailure,
        onDone: _handleConnectionClosed,
      );
      _state = SyncConnectionState.connected;
      _lastError = null;
      _reconnectAttempt = 0;
      _lastSyncTimestamp = DateTime.now();
      notifyListeners();
      await onReconnected?.call();
    } catch (error) {
      _handleConnectionFailure(error);
    }
  }

  Future<void> disconnect() async {
    _manuallyDisconnected = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _messages?.cancel();
    _messages = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
    _state = SyncConnectionState.disconnected;
    notifyListeners();
  }

  void _handleMessage(Object? message) {
    final event = SyncEvent.tryParse(message);
    if (event == null) return;
    _lastSyncTimestamp = event.occurredAt;
    notifyListeners();
    onSyncEvent?.call(event);
  }

  void _handleConnectionClosed() {
    if (!_manuallyDisconnected) _handleConnectionFailure(null);
  }

  void _handleConnectionFailure(Object? error) {
    _messages?.cancel();
    _messages = null;
    _socket = null;
    if (_manuallyDisconnected) return;
    _state = SyncConnectionState.reconnecting;
    _lastError = error?.toString();
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_retryTimer != null || _manuallyDisconnected) return;
    final exponent = _reconnectAttempt.clamp(0, 5);
    final delay = Duration(seconds: 1 << exponent);
    _reconnectAttempt++;
    if (_reconnectDelay != null) {
      _reconnectDelay(delay);
      return;
    }
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      connect();
    });
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
