import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/domain/transaction_item.dart';
import 'package:frontend/ui/uncategorized_review_banner.dart';
import 'package:frontend/ui/dashboard_screen.dart';

void main() {
  testWidgets('UncategorizedReviewBanner renders when pending transactions exist', (WidgetTester tester) async {
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

  testWidgets('DashboardScreen displays review banner and opens review modal', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DashboardScreen(),
      ),
    );

    expect(find.text('Review Required (2)'), findsOneWidget);
    await tester.tap(find.text('1-Tap Review'));
    await tester.pumpAndSettle();

    expect(find.text('Review Transactions'), findsOneWidget);
    expect(find.text('Confirm Category'), findsWidgets);
    expect(find.text('1-Tap Merge'), findsWidgets);
  });
}
