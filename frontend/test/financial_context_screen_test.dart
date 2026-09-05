import 'package:automatic_expense_tracker/domain/financial_context_item.dart';
import 'package:automatic_expense_tracker/ui/financial_context_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'renders provenance, consumer capabilities, and insufficient state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FinancialContextScreen(
        load: () async => FinancialContextList(
          asOf: DateTime.utc(2026, 8, 29),
          items: [
            FinancialContextItem(
              id: 'ctx-expired',
              type: 'MAJOR_PURCHASE_INTENTION',
              label: 'Laptop replacement',
              values: const {
                'plannedAmount': '75000.00',
                'currency': 'INR',
                'targetDate': '2026-10-01',
              },
              capabilities: const ['CASH_FLOW_FORECAST'],
              provenance: 'USER_DECLARED',
              active: true,
              createdAt: DateTime.utc(2026, 8, 1),
              updatedAt: DateTime.utc(2026, 8, 1),
              status: 'EXPIRED',
            ),
          ],
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Laptop replacement'), findsOneWidget);
    expect(find.text('Provenance: User Declared'), findsOneWidget);
    expect(find.text('Cash Flow Forecast'), findsOneWidget);
    expect(
        find.textContaining('Insufficient eligible context'), findsOneWidget);
  });

  testWidgets('shows an actionable server error and retries', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: FinancialContextScreen(
        load: () async {
          attempts++;
          if (attempts == 1) throw StateError('offline');
          return FinancialContextList(
              asOf: DateTime.utc(2026, 8, 29), items: const []);
        },
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('Financial context is unavailable'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.textContaining('No financial context yet'), findsOneWidget);
  });
}
