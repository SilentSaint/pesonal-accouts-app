import 'package:flutter/material.dart';
import '../domain/transaction_item.dart';

class TransactionReviewModal extends StatelessWidget {
  final List<TransactionItem> pendingTransactions;
  final Function(TransactionItem item, String category) onConfirm;
  final Function(TransactionItem targetItem, TransactionItem duplicateItem) onMerge;

  const TransactionReviewModal({
    super.key,
    required this.pendingTransactions,
    required this.onConfirm,
    required this.onMerge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Review Transactions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (pendingTransactions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'All transactions reviewed!',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: pendingTransactions.length,
                itemBuilder: (context, index) {
                  final txn = pendingTransactions[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              txn.merchantName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${txn.currency} ${txn.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Color(0xFFF87171),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF334155),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Source: ${txn.ingestionSource}',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: txn.reconciliationStatus == 'NEEDS_REVIEW'
                                    ? const Color(0xFF78350F)
                                    : const Color(0xFF1E3A8A),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                txn.reconciliationStatus == 'NEEDS_REVIEW' ? 'Potential Duplicate' : 'Uncategorized',
                                style: TextStyle(
                                  color: txn.reconciliationStatus == 'NEEDS_REVIEW' ? const Color(0xFFFBBF24) : const Color(0xFF60A5FA),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  onConfirm(txn, 'Food & Dining');
                                  Navigator.of(context).pop();
                                },
                                icon: const Icon(Icons.check_circle_outline, size: 16),
                                label: const Text('Confirm Category'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF22C55E),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            if (index > 0 || pendingTransactions.length > 1) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    final otherTxn = pendingTransactions[(index + 1) % pendingTransactions.length];
                                    onMerge(txn, otherTxn);
                                    Navigator.of(context).pop();
                                  },
                                  icon: const Icon(Icons.merge_type, size: 16),
                                  label: const Text('1-Tap Merge'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B82F6),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
