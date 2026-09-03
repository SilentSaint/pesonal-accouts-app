import 'package:automatic_expense_tracker/domain/analytics_report.dart';
import 'package:automatic_expense_tracker/domain/transaction_item.dart';
import 'package:automatic_expense_tracker/ui/analytics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders server-derived report data and exports selected month',
      (tester) async {
    final exports = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AnalyticsScreen(
          loadReport: (_) async => _report,
          exportReport: (month, format) async => exports.add('$month:$format'),
          now: () => DateTime(2026, 8, 15),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('₹250.00'), findsOneWidget);
    expect(find.text('Dining'), findsWidgets);
    expect(find.textContaining('largest category'), findsOneWidget);

    await tester.tap(find.byTooltip('Export CSV'));
    await tester.pumpAndSettle();

    expect(exports, ['${_report.month}:csv']);
    expect(find.text('CSV report downloaded.'), findsOneWidget);
  });

  testWidgets('shows an error state and retries the report request',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AnalyticsScreen(
          loadReport: (_) async {
            attempts++;
            if (attempts == 1) throw StateError('offline');
            return _report;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Analytics are unavailable'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Dining'), findsWidgets);
  });

  testWidgets('loads server-filtered evidence for deterministic spending analytics',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnalyticsScreen(
          loadReport: (_) async => _spendingReport,
          loadEvidence: (_, __, ___) async => AnalyticsEvidencePage(
            items: [
              TransactionItem(
                id: 'txn-1',
                amount: 120,
                currency: 'INR',
                type: 'DEBIT',
                merchantName: 'Coffee Shop',
                accountId: 'account-1',
                ingestionSource: 'MANUAL',
                reconciliationStatus: 'CONFIRMED',
                timestamp: DateTime.utc(2026, 8, 2, 10),
                netPersonalExpense: 120,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('View calculation evidence'));
    await tester.pumpAndSettle();

    expect(find.text('Calculation details'), findsOneWidget);
    expect(find.text('Coffee Shop'), findsOneWidget);
    expect(find.textContaining('spending-analytics v1.0.0'), findsOneWidget);
  });
}

const _report = AnalyticsReport(
  month: '2026-08',
  currency: 'INR',
  transactionCount: 2,
  cashFlow: CashFlow(
    income: 1000,
    spending: 300,
    netPersonalExpense: 250,
    netSavings: 750,
  ),
  categoryTotals: [
    CategoryTotal(categoryId: 'Dining', total: 250, percentageOfTotal: 100),
  ],
  spendingTrend: [
    DailySpendingTrend(
      date: '2026-08-01',
      income: 1000,
      spending: 0,
      netPersonalExpense: 0,
    ),
  ],
  aiInsights: ['Dining is the largest category.'],
  insightSource: 'SERVER_DERIVED_FALLBACK',
);

const _spendingReport = AnalyticsReport(
  month: '2026-08',
  currency: 'INR',
  transactionCount: 1,
  cashFlow: CashFlow(
    income: 0,
    spending: 120,
    netPersonalExpense: 120,
    netSavings: 0,
  ),
  categoryTotals: [
    CategoryTotal(categoryId: 'Dining', total: 120, percentageOfTotal: 100),
  ],
  spendingTrend: [],
  aiInsights: ['INCOMPLETE PERIOD'],
  insightSource: 'FACT',
  isSpendingAnalytics: true,
  formulaId: 'spending-analytics',
  formulaVersion: '1.0.0',
);
