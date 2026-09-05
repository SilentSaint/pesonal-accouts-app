import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:automatic_expense_tracker/domain/transaction_item.dart';
import 'package:automatic_expense_tracker/domain/financial_account.dart';
import 'package:automatic_expense_tracker/services/auto_scan_scheduler_service.dart';
import 'package:automatic_expense_tracker/services/security_service.dart';
import 'package:automatic_expense_tracker/ui/dashboard_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'app_data_version': 5,
      'is_historical_backfilled': true,
    });
  });

  testWidgets('Accounts section renders 2-column grid without horizontal scrolling and computes live balance ledger', (WidgetTester tester) async {
    final recent = [
      TransactionItem(
        id: 'txn-debit-2650',
        amount: 2650.0,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Self Transfer',
        accountId: 'acc-1277',
        categoryId: 'Self Transfer',
        subCategory: 'Account to Account Transfer',
        accountMask: '•••• 1277',
        transferCounterpartMask: '•••• 9343',
        rawSnippet: 'Rs.2650.00 is debited from account ending 1277',
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime(2026, 8, 4, 9, 8),
      ),
      TransactionItem(
        id: 'txn-card-9207',
        amount: 706.82,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'ACT Fibernet',
        accountId: 'acc-9207',
        categoryId: 'Bills & Utilities',
        subCategory: 'Broadband & Internet',
        accountMask: '•••• 9207',
        rawSnippet: 'Rs. 706.82 has been debited from your HDFC Bank Credit Card ending 9207 towards HDFCBPBAND',
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime(2026, 8, 4, 11, 0),
      ),
    ];

    final initialAccounts = [
      FinancialAccount(
        id: 'acc-1277',
        name: 'HDFC Bank (•••• 1277)',
        type: 'SAVINGS',
        lastFourDigits: '1277',
        currentBalance: 50868.64,
        anchorBalance: 50868.64,
        anchorDate: DateTime(2026, 8, 3),
        currency: 'INR',
      ),
      FinancialAccount(
        id: 'acc-9207',
        name: 'Bank Account (•••• 9207)', // Old SAVINGS name, will be auto-classified to CREDIT_CARD
        type: 'SAVINGS',
        lastFourDigits: '9207',
        currentBalance: 0.0,
        currency: 'INR',
      ),
      FinancialAccount(
        id: 'acc-8173',
        name: 'Bank Account (•••• 8173)',
        type: 'SAVINGS',
        lastFourDigits: '8173',
        currentBalance: 0.0,
        currency: 'INR',
      ),
      FinancialAccount(
        id: 'acc-9343',
        name: 'Bank Account (•••• 9343)',
        type: 'SAVINGS',
        lastFourDigits: '9343',
        currentBalance: 0.0,
        currency: 'INR',
      ),
    ];

    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          initialRecentTransactions: recent,
          initialAccounts: initialAccounts,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // 1. Verify that accounts are laid out in a responsive Wrap grid
    expect(find.byType(Wrap), findsWidgets);
    // All 4 accounts must be rendered in the tree simultaneously
    expect(find.text('HDFC Bank (•••• 1277)'), findsOneWidget);
    expect(find.text('HDFC Credit Card (•••• 9207)'), findsOneWidget);
    expect(find.text('Bank Account (•••• 8173)'), findsOneWidget);
    expect(find.text('Bank Account (•••• 9343)'), findsOneWidget);

    // 2. Verify account type badges
    expect(find.text('SAVINGS'), findsWidgets);
    expect(find.text('CREDIT CARD'), findsOneWidget);

    // 3. Verify balance sheet ledger calculation:
    // Anchor 50,868.64 minus 2,650 debit = ₹48,218.64
    expect(find.text('₹48218.64'), findsOneWidget);

    // 4. Verify Credit card shows outstanding spend (₹706.82) on card and in recent txns
    expect(find.text('₹706.82'), findsNWidgets(2));
    expect(find.text('Current Spend / Outstanding'), findsOneWidget);

    AutoScanSchedulerService().stop();
    SecurityState().cancelIdleTimer();
    await tester.pumpAndSettle();
  });
}
