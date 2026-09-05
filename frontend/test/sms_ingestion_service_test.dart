import 'dart:async';

import 'package:automatic_expense_tracker/application/sms_ingestion_service.dart';
import 'package:automatic_expense_tracker/domain/sms_ingestion_port.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('acknowledges a durable SMS event only after canonical submission',
      () async {
    final port = _FakeSmsPort([_event()]);
    final service = SmsIngestionService(port);

    final result = await service.drain((transaction, event) async {
      expect(transaction.id, 'txn-sms-event-0001');
      expect(transaction.ingestionSource, 'SMS');
      expect(transaction.accountMask, '•••• 1234');
      return true;
    });

    expect(result.delivered, 1);
    expect(result.retainedForRetry, 0);
    expect(port.acknowledged, ['event-0001']);
  });

  test('retains failed submission for retry without generating a new event',
      () async {
    final port = _FakeSmsPort([_event()]);
    final service = SmsIngestionService(port);

    final first = await service.drain((_, __) async => false);
    expect(first.retainedForRetry, 1);
    expect(port.acknowledged, isEmpty);

    final second = await service.drain((_, __) async => true);
    expect(second.delivered, 1);
    expect(port.acknowledged, ['event-0001']);
  });

  test('serializes simultaneous drains to prevent duplicate submission',
      () async {
    final port = _FakeSmsPort([_event()]);
    final service = SmsIngestionService(port);
    final submitted = Completer<bool>();
    var calls = 0;

    final first = service.drain((_, __) {
      calls++;
      return submitted.future;
    });
    final second = service.drain((_, __) {
      calls++;
      return submitted.future;
    });

    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    submitted.complete(true);
    await Future.wait([first, second]);
    expect(port.acknowledged, ['event-0001']);
  });

  test('does not expose raw SMS text in its durable public event seam', () {
    final transaction = _event().toTransaction();
    expect(transaction.rawSnippet, isNull);
    expect(transaction.referenceNumber, isNull);
  });
}

class _FakeSmsPort implements SmsIngestionPort {
  _FakeSmsPort(this.events);

  final List<SmsCaptureEvent> events;
  final List<String> acknowledged = [];

  @override
  Future<void> acknowledge(String eventId) async {
    acknowledged.add(eventId);
    events.removeWhere((event) => event.id == eventId);
  }

  @override
  Future<SmsCaptureStatus> captureStatus() async => const SmsCaptureStatus(
        isSupported: true,
        isEnabled: true,
        hasReceivePermission: true,
      );

  @override
  Future<void> initialize(void Function() onEventAvailable) async {}

  @override
  Future<List<SmsCaptureEvent>> pendingEvents() async => List.of(events);

  @override
  Future<SmsCaptureStatus> requestCaptureAuthorization() => captureStatus();
}

SmsCaptureEvent _event() => SmsCaptureEvent(
      id: 'event-0001',
      amount: 125,
      type: 'DEBIT',
      merchantName: 'Coffee Shop',
      bankName: 'Example Bank',
      accountLastFour: '1234',
      categoryId: 'Food & Dining',
      timestamp: DateTime.utc(2026, 8, 29),
    );
