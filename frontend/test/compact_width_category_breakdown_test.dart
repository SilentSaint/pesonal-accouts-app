import 'package:automatic_expense_tracker/ui/category_breakdown_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('category breakdown wraps its total badge at compact width',
      (tester) async {
    tester.view.physicalSize = const Size(512, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CategoryBreakdownView(
            categoryTotals: {'Groceries': 100},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Category Spending Breakdown'), findsOneWidget);
    expect(find.text('₹100 total'), findsOneWidget);
  });
}
