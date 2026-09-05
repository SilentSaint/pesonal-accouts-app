import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:automatic_expense_tracker/domain/transaction_item.dart';
import 'package:automatic_expense_tracker/domain/financial_account.dart';
import 'package:automatic_expense_tracker/services/auto_scan_scheduler_service.dart';
import 'package:automatic_expense_tracker/ui/dashboard_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'app_data_version': 5,
      'is_historical_backfilled': true,
    });
  });

  testWidgets('DashboardScreen reconciles self-transfer pairs and displays route and accounts in details modal', (WidgetTester tester) async {
    final debitSnippet = 'Dear Customer, Greetings from HDFC Bank! Rs.2650.00 is debited from your account ending 1277 towards VPA 7813004130@axl (RAKSHITH GOWDA G) on 04-08-26. UPI transaction reference no.: 621688749845. If';
    final creditSnippet = 'BANNER IMAGE 04-08-2026 Dear Rakshith Gowda G, Here&#39;s the summary of your transaction: Amount Credited: INR 2650.00 Account Number: XX9343 Date &amp; Time: 04-08-26, 09:08:03 IST Transaction Info:';

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
        transferCounterpartMask: null,
        rawSnippet: debitSnippet,
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime(2026, 8, 4, 9, 8),
      ),
      TransactionItem(
        id: 'txn-credit-2650',
        amount: 2650.0,
        currency: 'INR',
        type: 'CREDIT',
        merchantName: 'Self Transfer',
        accountId: 'acc-gmail',
        categoryId: 'Self Transfer',
        subCategory: 'Account to Account Transfer',
        accountMask: '•••• 1277 →', // Erroneous unlinked mask from earlier iteration
        transferCounterpartMask: null,
        rawSnippet: creditSnippet,
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: DateTime(2026, 8, 4, 9, 8, 3),
      ),
    ];

    final initialAccounts = [
      FinancialAccount(
        id: 'acc-1277',
        name: 'HDFC Bank (•••• 1277)',
        type: 'SAVINGS',
        lastFourDigits: '1277',
        currentBalance: 50000.0,
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
    await tester.pumpAndSettle();

    // 1. Assert that the self-transfer badge displays the complete route: •••• 1277 → •••• 9343
    expect(find.text('•••• 1277 → •••• 9343'), findsWidgets);

    // 2. Assert that the to-account (9343) was recognized and registered in accounts
    expect(find.text('Bank Account (•••• 9343)'), findsWidgets);

    // 3. Tap the transaction tile to open the Transaction Details Modal
    final tileFinder = find.text('•••• 1277 → •••• 9343').first;
    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    // 4. Assert that the details tile displays:
    // - Transfer Route: •••• 1277 → •••• 9343
    // - Debited From: •••• 1277
    // - Credited To: •••• 9343
    expect(find.text('Transfer Route'), findsOneWidget);
    expect(find.text('Debited From'), findsOneWidget);
    expect(find.text('Credited To'), findsOneWidget);
    expect(find.text('•••• 1277'), findsWidgets);
    expect(find.text('•••• 9343'), findsWidgets);

    AutoScanSchedulerService().stop();
    await tester.pumpAndSettle();
  });
}
