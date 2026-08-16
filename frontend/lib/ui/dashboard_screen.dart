import 'package:flutter/material.dart';
import '../domain/financial_account.dart';
import '../domain/transaction_item.dart';
import 'uncategorized_review_banner.dart';
import 'historical_backfill_card.dart';
import 'category_breakdown_view.dart';
import 'transaction_review_modal.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool isScanning30Days = false;

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

  final Map<String, double> categoryTotals = {
    'Food & Dining': 1850.00,
    'Shopping': 2450.00,
    'Transport & Fuel': 650.00,
    'Bills & Utilities': 1200.00,
  };

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

  void _run30DayBackfillScan() async {
    setState(() {
      isScanning30Days = true;
    });

    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      isScanning30Days = false;
      accounts.add(
        FinancialAccount(
          id: 'acc-auto-9988',
          name: 'ICICI Card',
          type: 'CREDIT_CARD',
          lastFourDigits: '9988',
          currency: 'INR',
          currentBalance: -1200.00,
        ),
      );
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('30-Day Scan Complete! Auto-discovered 1 new account & 14 historical transactions.'),
          backgroundColor: Color(0xFF6366F1),
        ),
      );
    }
  }

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
            HistoricalBackfillCard(
              onScanPressed: _run30DayBackfillScan,
              isScanning: isScanning30Days,
            ),
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
                            Expanded(
                              child: Text(
                                acc.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
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
            const SizedBox(height: 16),
            CategoryBreakdownView(categoryTotals: categoryTotals),
          ],
        ),
      ),
    );
  }
}
