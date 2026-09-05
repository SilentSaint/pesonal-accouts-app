import 'package:automatic_expense_tracker/domain/transaction_item.dart';
import 'package:automatic_expense_tracker/services/auth_service.dart';
import 'package:automatic_expense_tracker/services/auto_scan_scheduler_service.dart';
import 'package:automatic_expense_tracker/ui/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'auth_email': 'reviewer@example.com',
      'auth_display_name': 'Reviewer',
      'auth_scope_id': 'reviewer-scope',
    });
    await AuthService().ensureInitialized();
  });

  testWidgets('one confirmation persists matching payees and removes only saved reviews',
      (tester) async {
    tester.view.physicalSize = const Size(3000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      AutoScanSchedulerService().stop();
    });
    final persisted = <TransactionItem>[];

    await tester.pumpWidget(MaterialApp(
      home: DashboardScreen(
        initialPendingTransactions: [
          _review('first', 'Saira Banu', 'paytm.s1yxlpq@pty'),
          _review('matching', 'Bank Alert', 'paytm.s1yxlpq@pty'),
          _review('unrelated', 'Other Merchant', 'another.shop@upi'),
        ],
        onReviewConfirmation: (transaction) async {
          persisted.add(transaction);
          return transaction;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1-Tap Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom Alias').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('review-custom-alias-input')), 'Green Market');
    tester.widget<DropdownButton<String>>(
      find.byKey(const Key('review-custom-alias-category-first')),
    ).onChanged!('Groceries');
    await tester.pumpAndSettle();
    tester.widget<DropdownButton<String>>(
      find.byKey(const Key('review-custom-alias-subcategory-first')),
    ).onChanged!('Fruits & Vegetables');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-save-custom-alias')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-confirm-first')));
    await tester.pumpAndSettle();

    expect(persisted.map((item) => item.id), ['first', 'matching']);
    expect(persisted, everyElement(isA<TransactionItem>()
        .having((item) => item.merchantName, 'merchant', 'Green Market')
        .having((item) => item.categoryId, 'category', 'Groceries')
        .having((item) => item.subCategory, 'subcategory', 'Fruits & Vegetables')
        .having((item) => item.reconciliationStatus, 'status', 'CONFIRMED')));
    expect(find.byKey(const Key('review-confirm-first')), findsNothing);
    expect(find.byKey(const Key('review-confirm-matching')), findsNothing);
    expect(find.byKey(const Key('review-confirm-unrelated')), findsOneWidget);

    AutoScanSchedulerService().stop();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

TransactionItem _review(String id, String merchant, String vpa) => TransactionItem(
      id: id,
      amount: 100,
      currency: 'INR',
      type: 'DEBIT',
      merchantName: merchant,
      accountId: 'account',
      categoryId: 'General Expenses',
      ingestionSource: 'EMAIL',
      reconciliationStatus: 'NEEDS_REVIEW',
      timestamp: DateTime.utc(2026, 9, 5),
      referenceNumber: '${id}123456789',
      rawSnippet: 'Debited towards VPA $vpa ($merchant)',
    );
