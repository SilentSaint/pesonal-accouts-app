import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:automatic_expense_tracker/ui/email_settings_screen.dart';

void main() {
  testWidgets('EmailSettingsScreen renders and allows linking email account', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EmailSettingsScreen(),
      ),
    );

    expect(find.text('Linked Email Accounts'), findsOneWidget);
    expect(find.text('Link Financial Email Account'), findsOneWidget);
    expect(find.text('user.personal@gmail.com'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'test.finance@gmail.com');
    await tester.tap(find.text('Link Account'));
    await tester.pumpAndSettle();

    expect(find.text('test.finance@gmail.com'), findsOneWidget);
  });
}
