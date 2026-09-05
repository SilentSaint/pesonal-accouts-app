import 'package:automatic_expense_tracker/domain/financial_goal.dart';
import 'package:automatic_expense_tracker/ui/financial_goal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows required pace, projection and insufficient-data state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FinancialGoalScreen(
        load: () async => FinancialGoalList(
          asOf: DateTime.utc(2026, 3, 1),
          goals: [
            FinancialGoal(
              id: 'car',
              name: 'Car',
              targetAmount: '1200.00',
              currency: 'INR',
              targetDate: DateTime.utc(2026, 6, 30),
              priority: 'HIGH',
              lifecycle: 'ACTIVE',
              allocations: const [],
              contributions: const [],
              contributionRule: null,
              projection: FinancialGoalProjection(
                amountRemaining: '800.00',
                currency: 'INR',
                monthsRemaining: 4,
                requiredMonthlyContribution: '200.00',
                observedMonthlyContribution: '0.00',
                projectedCompletionDate: null,
                monthlyShortfallOrSurplus: '-200.00',
                minimumBalanceBreached: false,
                status: 'INSUFFICIENT_DATA',
                classification: 'PREDICTION',
                formulaId: 'financial-goal-projection',
                formulaVersion: '1.0.0',
                confidence: '0.25',
                assumptions: const [],
                warnings: const ['INSUFFICIENT_HISTORY'],
                contributionEvidenceReferences: const [],
              ),
            ),
          ],
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('INR 200.00 / month required'), findsOneWidget);
    expect(find.text('Projection needs contribution data'), findsOneWidget);
  });
}
