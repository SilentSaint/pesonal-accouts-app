import '../domain/transaction_item.dart';

class ReconciliationReviewQueue {
  const ReconciliationReviewQueue(
      this.pendingTransactions, this.canonicalTransactions);

  final List<TransactionItem> pendingTransactions;
  final List<TransactionItem> canonicalTransactions;
}
