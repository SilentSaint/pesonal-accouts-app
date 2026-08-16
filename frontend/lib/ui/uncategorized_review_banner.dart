import 'package:flutter/material.dart';
import '../domain/transaction_item.dart';

class UncategorizedReviewBanner extends StatelessWidget {
  final List<TransactionItem> pendingTransactions;
  final VoidCallback onReviewPressed;

  const UncategorizedReviewBanner({
    super.key,
    required this.pendingTransactions,
    required this.onReviewPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingTransactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final count = pendingTransactions.length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF451A03), Color(0xFF78350F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x80F59E0B), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1AF59E0B),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0x33F59E0B),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.rule_folder,
              color: Color(0xFFFBBF24),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review Required ($count)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'transactions need confirmation or deduplication',
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onReviewPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              '1-Tap Review',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
