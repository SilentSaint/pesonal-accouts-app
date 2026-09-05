import 'package:automatic_expense_tracker/domain/proactive_insight.dart';
import 'package:automatic_expense_tracker/ui/proactive_insights_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a persisted insight baseline and dismisses it',
      (tester) async {
    final dismissed = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: ProactiveInsightsScreen(
        loadInsights: () async => [_insight],
        dismissInsight: (id) async => dismissed.add(id),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('Category spending increased'), findsOneWidget);
    expect(find.textContaining('₹5,000.00'), findsOneWidget);
    expect(find.text('three comparable prior months'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss insight'));
    await tester.pumpAndSettle();

    expect(dismissed, ['insight-1']);
    expect(find.text('No current insights'), findsOneWidget);
  });

  testWidgets(
      'shows an insufficient-data state distinctly from a loading failure',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProactiveInsightsScreen(loadInsights: () async => const []),
    ));

    await tester.pumpAndSettle();
    expect(find.text('Not enough history yet'), findsOneWidget);
    expect(find.textContaining('three comparable months'), findsOneWidget);
  });
}

const _insight = ProactiveInsight(
  id: 'insight-1',
  type: 'CATEGORY_INCREASE',
  classification: 'DERIVED_INSIGHT',
  title: 'Category spending increased',
  message: 'category GROCERIES is 150% higher than your usual spending.',
  currentAmount: InsightMoney(amount: 5000, currency: 'INR'),
  baselineAmount: InsightMoney(amount: 2000, currency: 'INR'),
  baselineLabel: 'three comparable prior months',
  confidence: 0.9,
  freshnessAsOf: '2026-08-31T18:30:00Z',
  matchingTransactions: [
    InsightTransaction(
        transactionId: 'txn-1', merchantName: 'Grocer', personalSpend: 5000),
  ],
);
