import 'package:automatic_expense_tracker/domain/recurring_commitment.dart';
import 'package:automatic_expense_tracker/ui/recurring_commitments_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('distinguishes candidates and variable changed amounts',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecurringCommitmentsScreen(
        load: () async => RecurringCommitmentList(
          asOf: DateTime.utc(2026, 3, 6),
          commitments: [
            _commitment(
                id: 'candidate', status: 'CANDIDATE', state: 'ON_TRACK'),
            _commitment(
                id: 'utility', status: 'CONFIRMED', state: 'VARIABLE_AMOUNT'),
          ],
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Possible recurring commitments'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Variable amount'), findsOneWidget);
  });

  testWidgets('explains when transaction history is insufficient',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecurringCommitmentsScreen(
        load: () async => RecurringCommitmentList(
          asOf: DateTime.utc(2026, 3, 6),
          commitments: const [],
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.textContaining('Need at least two matching'), findsOneWidget);
  });
}

RecurringCommitment _commitment({
  required String id,
  required String status,
  required String state,
}) =>
    RecurringCommitment(
      id: id,
      name: id == 'utility' ? 'City Electricity' : 'StreamFlix',
      classification: id == 'utility' ? 'UTILITY' : 'SUBSCRIPTION',
      cadence: 'MONTHLY',
      minimumAmount: id == 'utility' ? '800.00' : '499.00',
      maximumAmount: id == 'utility' ? '1300.00' : '499.00',
      currency: 'INR',
      nextPaymentDate: DateTime.utc(2026, 4, 5),
      confidence: 0.85,
      supportingTransactionIds: const ['one', 'two'],
      status: status,
      state: state,
      origin: 'DETECTED',
    );
