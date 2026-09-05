import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:automatic_expense_tracker/ui/dashboard_screen.dart';
import 'package:automatic_expense_tracker/domain/transaction_item.dart';

void main() {
  testWidgets('DashboardScreen renders desktop adaptive layout with Hero Card and Nav', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final testPending = [
      TransactionItem(
        id: 'txn-test-1',
        amount: 350.0,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Starbucks',
        accountId: 'acc-1',
        ingestionSource: 'SMS',
        reconciliationStatus: 'NEEDS_REVIEW',
        timestamp: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(initialPendingTransactions: testPending),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // Verify Brand Title & Status
    expect(find.text('Expense Tracker'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);

    // Verify Hero Card Metrics
    expect(find.text('TOTAL NET LIQUIDITY'), findsOneWidget);
    expect(find.text('Total Outflow'), findsOneWidget);
    expect(find.text('Total Inflow'), findsOneWidget);

    // Verify Quick Actions in Hero Card
    expect(find.text('Import Text'), findsOneWidget);
    expect(find.text('Add Account'), findsOneWidget);

    // Verify Review Banner
    expect(find.text('Review Required (1)'), findsOneWidget);
    expect(find.text('1-Tap Review'), findsOneWidget);

    // Verify Peer Debt Card
    expect(find.text('Peer Lending & Debt Ledger'), findsOneWidget);

    // Verify Sections
    expect(find.text('Your Accounts'), findsOneWidget);
    expect(find.text('Recent Transactions'), findsOneWidget);
  });

  testWidgets('DashboardScreen renders mobile layout without overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: DashboardScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // Verify Essential Components Render on Mobile
    expect(find.text('Expense Tracker'), findsOneWidget);
    expect(find.text('TOTAL NET LIQUIDITY'), findsOneWidget);
    expect(find.text('Your Accounts'), findsOneWidget);
    expect(find.text('Recent Transactions'), findsOneWidget);
  });
}
