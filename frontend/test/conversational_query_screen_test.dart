import 'package:automatic_expense_tracker/domain/conversational_finance_query.dart';
import 'package:automatic_expense_tracker/ui/conversational_query_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('submits a spending question and exposes its evidence action',
      (tester) async {
    ConversationDrillDown? selectedEvidence;
    await tester.pumpWidget(MaterialApp(
      home: ConversationalQueryScreen(
        askQuestion: (question) async =>
            const ConversationalFinanceQueryResponse.answer(
          observation:
              'Personal spending for the selected period is INR 300.00.',
          asOf: '2026-08-31T18:30:00Z',
          sourceCount: 2,
          drillDown: ConversationDrillDown(
            start: '2026-08-01',
            end: '2026-08-31',
            currency: 'INR',
            accountIds: [],
          ),
        ),
        onEvidenceRequested: (drillDown) => selectedEvidence = drillDown,
      ),
    ));

    await tester.enterText(
      find.bySemanticsLabel('Spending question'),
      'How much did I spend this month?',
    );
    await tester.tap(find.bySemanticsLabel('Ask spending question'));
    await tester.pumpAndSettle();

    expect(
        find.text('Personal spending for the selected period is INR 300.00.'),
        findsOneWidget);
    expect(
        find.bySemanticsLabel('View supporting transactions'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('View supporting transactions'));
    expect(selectedEvidence?.start, '2026-08-01');
  });

  testWidgets('keeps the question available for retry after an error',
      (tester) async {
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
      home: ConversationalQueryScreen(
        askQuestion: (question) async {
          requests++;
          if (requests == 1) throw StateError('offline');
          return const ConversationalFinanceQueryResponse.clarification(
              'Please select a period.');
        },
      ),
    ));

    await tester.enterText(
        find.bySemanticsLabel('Spending question'), 'Compare spending');
    await tester.tap(find.bySemanticsLabel('Ask spending question'));
    await tester.pumpAndSettle();
    expect(find.text('Your question could not be answered.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(find.text('Please select a period.'), findsOneWidget);
  });
}
