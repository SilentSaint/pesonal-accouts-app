import 'package:flutter/material.dart';
import '../domain/financial_account.dart';
import '../domain/transaction_item.dart';
import 'uncategorized_review_banner.dart';
import 'transaction_review_modal.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<FinancialAccount> accounts = [
    FinancialAccount(
      id: 'acc-1',
      name: 'HDFC Salary Account',
      type: 'SAVINGS',
      lastFourDigits: '1234',
      currency: 'INR',
      currentBalance: 9500.00,
    ),
    FinancialAccount(
      id: 'acc-2',
      name: 'SBI Credit Card',
      type: 'CREDIT_CARD',
      lastFourDigits: '5678',
      currency: 'INR',
      currentBalance: -250.00,
    ),
  ];

  final List<TransactionItem> pendingTransactions = [
    TransactionItem(
      id: 'txn-review-1',
      amount: 499.00,
      currency: 'INR',
      type: 'DEBIT',
      merchantName: 'Swiggy Pay',
      accountId: 'acc-1',
      categoryId: null,
      ingestionSource: 'EMAIL',
      reconciliationStatus: 'NEEDS_REVIEW',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    TransactionItem(
      id: 'txn-review-2',
      amount: 499.00,
      currency: 'INR',
      type: 'DEBIT',
      merchantName: 'Bundl Tech',
      accountId: 'acc-1',
      categoryId: null,
      ingestionSource: 'SMS',
      reconciliationStatus: 'NEEDS_REVIEW',
      timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
    ),
  ];

  void _openReviewModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TransactionReviewModal(
        pendingTransactions: pendingTransactions,
        onConfirm: (txn, category) {
          setState(() {
            pendingTransactions.removeWhere((t) => t.id == txn.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Transaction confirmed under "$category"'),
              backgroundColor: const Color(0xFF22C55E),
            ),
          );
        },
        onMerge: (target, duplicate) {
          setState(() {
            pendingTransactions.removeWhere((t) => t.id == target.id || t.id == duplicate.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('1-Tap Merge complete: Duplicate merged successfully!'),
              backgroundColor: Color(0xFF3B82F6),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          'Automatic Expense Tracker',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UncategorizedReviewBanner(
              pendingTransactions: pendingTransactions,
              onReviewPressed: _openReviewModal,
            ),
            const Text(
              'Your Accounts',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: accounts.length,
                itemBuilder: (context, index) {
                  final acc = accounts[index];
                  return Container(
                    width: 260,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF334155), Color(0xFF1E293B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              acc.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '•••• ${acc.lastFourDigits}',
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Balance',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            Text(
                              '${acc.currency} ${acc.currentBalance.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: acc.currentBalance >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
      ),
    );
  }
}
