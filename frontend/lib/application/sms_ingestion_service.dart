import '../domain/sms_ingestion_port.dart';
import '../domain/transaction_item.dart';

class SmsIngestionResult {
  const SmsIngestionResult({
    required this.delivered,
    required this.retainedForRetry,
  });

  final int delivered;
  final int retainedForRetry;
}

/// Drains native durable SMS events only after their canonical transaction is
/// accepted by the authenticated transaction submission seam.
class SmsIngestionService {
  SmsIngestionService(this._port);

  final SmsIngestionPort _port;
  Future<SmsIngestionResult>? _activeDrain;

  Future<void> initialize(void Function() onEventAvailable) =>
      _port.initialize(onEventAvailable);

  Future<SmsCaptureStatus> captureStatus() => _port.captureStatus();

  Future<SmsCaptureStatus> requestCaptureAuthorization() =>
      _port.requestCaptureAuthorization();

  Future<SmsIngestionResult> drain(
    Future<bool> Function(TransactionItem transaction, SmsCaptureEvent event)
        submit,
  ) {
    return _activeDrain ??= _drain(submit).whenComplete(() {
      _activeDrain = null;
    });
  }

  Future<SmsIngestionResult> _drain(
    Future<bool> Function(TransactionItem transaction, SmsCaptureEvent event)
        submit,
  ) async {
    var delivered = 0;
    var retainedForRetry = 0;
    for (final event in await _port.pendingEvents()) {
      if (!event.isValid) {
        // An invalid native record cannot become valid through retries.
        await _port.acknowledge(event.id);
        continue;
      }
      try {
        if (await submit(event.toTransaction(), event)) {
          await _port.acknowledge(event.id);
          delivered++;
        } else {
          retainedForRetry++;
        }
      } catch (_) {
        retainedForRetry++;
      }
    }
    return SmsIngestionResult(
      delivered: delivered,
      retainedForRetry: retainedForRetry,
    );
  }
}
