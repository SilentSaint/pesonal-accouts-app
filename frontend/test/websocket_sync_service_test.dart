import 'dart:async';

import 'package:automatic_expense_tracker/services/websocket_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSyncSocket implements SyncSocket {
  final messages = StreamController<Object?>();
  var closed = false;

  @override
  Stream<Object?> get stream => messages.stream;

  @override
  Future<void> close() async {
    closed = true;
    await messages.close();
  }
}

void main() {
  test('authenticated clients receive canonical events from the live socket',
      () async {
    final socket = FakeSyncSocket();
    Uri? connectedUri;
    final events = <SyncEvent>[];
    final service = WebSocketSyncService.forTesting(
      endpointProvider: () => 'wss://sync.example.com/dev',
      tokenProvider: () => 'google-id-token',
      connector: (uri) async {
        connectedUri = uri;
        return socket;
      },
      reconnectDelay: (_) {},
    );
    service.onSyncEvent = events.add;

    await service.connect();
    socket.messages.add(
      '{"version":1,"type":"TRANSACTION_UPSERTED","entityId":"txn-42",'
      '"payload":{"id":"txn-42","amount":450},"occurredAt":"2026-08-29T06:00:00.000Z"}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(connectedUri!.queryParameters['token'], 'google-id-token');
    expect(service.state, SyncConnectionState.connected);
    expect(events.single.entityId, 'txn-42');
    expect(events.single.type, 'TRANSACTION_UPSERTED');
  });

  test(
      'a disconnect reconnects and requests state recovery without simulated success',
      () async {
    final firstSocket = FakeSyncSocket();
    final secondSocket = FakeSyncSocket();
    var attempts = 0;
    var recoveryCalls = 0;
    final delays = <Duration>[];
    final service = WebSocketSyncService.forTesting(
      endpointProvider: () => 'wss://sync.example.com/dev',
      tokenProvider: () => 'google-id-token',
      connector: (_) async => ++attempts == 1 ? firstSocket : secondSocket,
      reconnectDelay: (delay) => delays.add(delay),
    );
    service.onReconnected = () async => recoveryCalls++;

    await service.connect();
    await firstSocket.messages.close();
    await Future<void>.delayed(Duration.zero);
    await service.connect();

    expect(delays, [const Duration(seconds: 1)]);
    expect(service.state, SyncConnectionState.connected);
    expect(recoveryCalls, 2);
  });
}
