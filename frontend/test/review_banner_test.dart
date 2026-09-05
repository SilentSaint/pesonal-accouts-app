import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:automatic_expense_tracker/domain/transaction_item.dart';
import 'package:automatic_expense_tracker/ui/uncategorized_review_banner.dart';
import 'package:automatic_expense_tracker/ui/dashboard_screen.dart';

void main() {
  testWidgets(
      'UncategorizedReviewBanner renders when pending transactions exist',
      (WidgetTester tester) async {
    final pending = [
      TransactionItem(
        id: '1',
        amount: 499.00,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Swiggy',
        accountId: 'acc-1',
        ingestionSource: 'SMS',
        reconciliationStatus: 'NEEDS_REVIEW',
        timestamp: DateTime.now(),
      ),
    ];

    bool pressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UncategorizedReviewBanner(
            pendingTransactions: pending,
            onReviewPressed: () {
              pressed = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Review Required (1)'), findsOneWidget);
    expect(find.text('1-Tap Review'), findsOneWidget);

    await tester.tap(find.text('1-Tap Review'));
    expect(pressed, isTrue);
  });

  testWidgets('DashboardScreen displays review banner and opens review modal',
      (WidgetTester tester) async {
    final pending = [
      TransactionItem(
        id: '1',
        amount: 499.00,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Swiggy',
        accountId: 'acc-1',
        ingestionSource: 'SMS',
        reconciliationStatus: 'NEEDS_REVIEW',
        timestamp: DateTime.now(),
      ),
      TransactionItem(
        id: '2',
        amount: 499.00,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Swiggy',
        accountId: 'acc-1',
        ingestionSource: 'SMS',
        reconciliationStatus: 'NEEDS_REVIEW',
        potentialDuplicateOfTransactionId: '1',
        timestamp: DateTime.now(),
      ),
    ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(initialPendingTransactions: pending),
      ),
    );

    expect(find.text('Review Required (2)'), findsOneWidget);
    await tester.ensureVisible(find.text('1-Tap Review'));
    await tester.tap(find.text('1-Tap Review'));
    await tester.pumpAndSettle();

    expect(find.text('Review Transactions'), findsOneWidget);
    expect(find.text('Confirm Expense'), findsWidgets);
    expect(find.text('1-Tap Merge'), findsWidgets);
  });
}
