import 'transaction_item.dart';

class SmsCaptureStatus {
  const SmsCaptureStatus({
    required this.isSupported,
    required this.isEnabled,
    required this.hasReceivePermission,
  });

  final bool isSupported;
  final bool isEnabled;
  final bool hasReceivePermission;

  bool get isCapturing => isSupported && isEnabled && hasReceivePermission;

  factory SmsCaptureStatus.fromMap(Map<Object?, Object?> map) {
    bool value(String key) => map[key] == true;
    return SmsCaptureStatus(
      isSupported: value('supported'),
      isEnabled: value('enabled'),
      hasReceivePermission: value('hasReceivePermission'),
    );
  }
}

/// A privacy-minimised, durably stored representation of a financial SMS.
///
/// The original SMS body is deliberately not retained or sent across this seam.
class SmsCaptureEvent {
  const SmsCaptureEvent({
    required this.id,
    required this.amount,
    required this.type,
    required this.merchantName,
    required this.bankName,
    required this.accountLastFour,
    required this.categoryId,
    required this.timestamp,
  });

  final String id;
  final double amount;
  final String type;
  final String merchantName;
  final String bankName;
  final String accountLastFour;
  final String categoryId;
  final DateTime timestamp;

  bool get isValid =>
      id.isNotEmpty &&
      amount > 0 &&
      (type == 'DEBIT' || type == 'CREDIT') &&
      accountLastFour.length == 4;

  TransactionItem toTransaction() => TransactionItem(
        id: 'txn-sms-$id',
        amount: amount,
        currency: 'INR',
        type: type,
        merchantName: merchantName,
        accountId: 'acc-real-$accountLastFour',
        categoryId: categoryId,
        ingestionSource: 'SMS',
        reconciliationStatus: 'CONFIRMED',
        timestamp: timestamp,
        accountMask: '•••• $accountLastFour',
      );

  factory SmsCaptureEvent.fromMap(Map<Object?, Object?> map) {
    final timestamp = map['timestamp'];
    return SmsCaptureEvent(
      id: map['id'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      type: map['type'] as String? ?? '',
      merchantName: map['merchantName'] as String? ?? '',
      bankName: map['bankName'] as String? ?? '',
      accountLastFour: map['accountLastFour'] as String? ?? '',
      categoryId: map['categoryId'] as String? ?? 'General Expenses',
      timestamp: timestamp is num
          ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt())
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

abstract interface class SmsIngestionPort {
  Future<SmsCaptureStatus> captureStatus();
  Future<SmsCaptureStatus> requestCaptureAuthorization();
  Future<void> initialize(void Function() onEventAvailable);
  Future<List<SmsCaptureEvent>> pendingEvents();
  Future<void> acknowledge(String eventId);
}
