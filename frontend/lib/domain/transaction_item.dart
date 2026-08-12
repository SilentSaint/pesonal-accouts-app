class TransactionItem {
  final String id;
  final double amount;
  final String currency;
  final String type; // DEBIT or CREDIT
  final String merchantName;
  final String accountId;
  final String? categoryId;
  final String ingestionSource; // SMS, EMAIL, MANUAL
  final String reconciliationStatus; // CONFIRMED, NEEDS_REVIEW, AUTO_MERGED
  final DateTime timestamp;

  TransactionItem({
    required this.id,
    required this.amount,
    required this.currency,
    required this.type,
    required this.merchantName,
    required this.accountId,
    this.categoryId,
    required this.ingestionSource,
    required this.reconciliationStatus,
    required this.timestamp,
  });

  bool get needsReview => reconciliationStatus == 'NEEDS_REVIEW' || categoryId == null;
}
