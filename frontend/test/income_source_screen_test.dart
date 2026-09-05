import 'package:automatic_expense_tracker/domain/income_source.dart';
import 'package:automatic_expense_tracker/ui/income_source_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows an actionable empty income state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: IncomeSourceScreen(
        load: () async => const IncomeSourceList(sources: [], suggestions: []),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.textContaining('No confirmed income sources'), findsOneWidget);
    expect(find.text('Add income source'), findsOneWidget);
  });

  testWidgets('labels irregular income and exposes confirmation controls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: IncomeSourceScreen(
        load: () async => IncomeSourceList(
          sources: [_source('income-1', 'VARIABLE', 'CONFIRMED')],
          suggestions: [
            IncomeSuggestion(
              source: _source('candidate-1', 'FIXED', 'PENDING'),
              confidence: 0.95,
            ),
          ],
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Irregular income'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });
}

IncomeSource _source(String id, String type, String status) => IncomeSource(
      id: id,
      name: 'Acme Payroll',
      type: type,
      amount: '75000.00',
      currency: 'INR',
      cadence: 'MONTHLY',
      effectiveFrom: DateTime.utc(2026, 1, 31),
      linkedAccountId: 'account-1',
      confirmationStatus: status,
      sourceTransactionIds: const ['credit-1'],
    );
