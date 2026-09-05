import 'dart:async';
import 'dart:convert';

import 'package:automatic_expense_tracker/domain/transaction_item.dart';
import 'package:automatic_expense_tracker/services/auth_service.dart';
import 'package:automatic_expense_tracker/services/auto_scan_scheduler_service.dart';
import 'package:automatic_expense_tracker/services/financial_data_cache.dart';
import 'package:automatic_expense_tracker/ui/dashboard_screen.dart';
import 'package:automatic_expense_tracker/ui/transaction_review_modal.dart';
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

  testWidgets(
      'review confirmation returns merchant, category, subcategory, and amount edits',
      (WidgetTester tester) async {
    final original = _reviewTransaction();
    TransactionItem? confirmed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionReviewModal(
            pendingTransactions: [original],
            onConfirm: (item, _) {
              confirmed = item;
              return true;
            },
            onMerge: (_, __) {},
            onDismiss: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Custom Alias'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('review-custom-alias-input')),
      'Green Market',
    );
    await tester.pumpAndSettle();
    final categoryPicker = find
        .byKey(const Key('review-custom-alias-category-txn-review-00000001'));
    await tester.ensureVisible(categoryPicker);
    tester
        .widget<DropdownButton<String>>(categoryPicker)
        .onChanged!('Groceries');
    await tester.pumpAndSettle();
    final subcategoryPicker = find.byKey(
      const Key('review-custom-alias-subcategory-txn-review-00000001'),
    );
    await tester.ensureVisible(subcategoryPicker);
    tester
        .widget<DropdownButton<String>>(subcategoryPicker)
        .onChanged!('Fruits & Vegetables');
    await tester.tap(find.byKey(const Key('review-save-custom-alias')));
    await tester.pumpAndSettle();

    final amountEditor =
        find.byKey(const Key('review-amount-txn-review-00000001'));
    await tester.ensureVisible(amountEditor);
    await tester.tap(amountEditor);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('review-amount-input')),
      '913.42',
    );
    await tester.tap(find.text('Save Amount'));
    await tester.pumpAndSettle();

    final confirmButton =
        find.byKey(const Key('review-confirm-txn-review-00000001'));
    await tester.ensureVisible(confirmButton);
    tester.widget<ElevatedButton>(confirmButton).onPressed!();
    await tester.pumpAndSettle();

    expect(
      confirmed?.toJson(),
      _reviewTransaction(
        merchantName: 'Green Market',
        amount: 913.42,
        categoryId: 'Groceries',
        subCategory: 'Fruits & Vegetables',
      ).toJson(),
    );
  });

  testWidgets(
      'review confirmation shows saving and keeps the transaction retryable when rule learning fails',
      (WidgetTester tester) async {
    final saveResult = Completer<bool>();
    var confirmationCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionReviewModal(
            pendingTransactions: [_reviewTransaction()],
            onConfirm: (_, __) async {
              confirmationCalls++;
              return saveResult.future;
            },
            onMerge: (_, __) {},
            onDismiss: (_) {},
          ),
        ),
      ),
    );

    final confirmButton =
        find.byKey(const Key('review-confirm-txn-review-00000001'));
    await tester.ensureVisible(confirmButton);
    await tester.tap(confirmButton);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Saving category rule...'), findsOneWidget);

    saveResult.complete(false);
    await tester.pumpAndSettle();

    expect(confirmationCalls, 1);
    expect(
      find.text('Unable to save this category rule. Please try again.'),
      findsOneWidget,
    );
    expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNotNull);
  });

  testWidgets('review confirmation retains an edited transfer linkage',
      (WidgetTester tester) async {
    final transfer = _reviewTransaction(
      type: 'TRANSFER',
      merchantName: 'Self Transfer',
      categoryId: 'Self Transfer',
      subCategory: 'Wallet Top-up',
      transferCounterpartMask: '•••• 9876',
    );
    TransactionItem? confirmed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionReviewModal(
            pendingTransactions: [transfer],
            onConfirm: (item, _) {
              confirmed = item;
              return true;
            },
            onMerge: (_, __) {},
            onDismiss: (_) {},
          ),
        ),
      ),
    );

    final confirmButton =
        find.byKey(const Key('review-confirm-txn-review-00000001'));
    await tester.ensureVisible(confirmButton);
    tester.widget<ElevatedButton>(confirmButton).onPressed!();
    await tester.pumpAndSettle();

    expect(confirmed?.transferCounterpartMask, '•••• 9876');
    expect(confirmed?.categoryId, 'Self Transfer');
    expect(confirmed?.reconciliationStatus, 'NEEDS_REVIEW');
  });

  testWidgets(
      'dashboard confirms a review result unchanged and reloads the stored confirmed record',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(2000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      AutoScanSchedulerService().stop();
    });
    final reviewResult = _reviewTransaction(
      type: 'CREDIT',
      merchantName: 'Green Market',
      amount: 913.42,
      categoryId: 'Groceries',
      subCategory: 'Fruits & Vegetables',
      netPersonalExpense: 900,
      accountMask: '•••• 1234',
      referenceNumber: 'upi-12345678',
      rawSnippet: 'edited receipt',
      transferCounterpartMask: '•••• 9876',
    );
    final expected = reviewResult.copyWith(reconciliationStatus: 'CONFIRMED');

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          initialPendingTransactions: [reviewResult],
          onReviewConfirmation: (transaction) async => transaction,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final reviewButton = find.text('1-Tap Review');
    await tester.ensureVisible(reviewButton);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();
    final confirmButton =
        find.byKey(const Key('review-confirm-txn-review-00000001'));
    await tester.ensureVisible(confirmButton);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    final stored = (jsonDecode(
      preferences.getString(FinancialDataCache.recentTransactionsKey)!,
    ) as List<dynamic>)
        .single as Map<String, dynamic>;
    expect(TransactionItem.fromJson(stored).toJson(), expected.toJson());

    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Green Market'), findsWidgets);
    expect(find.text('+₹913.42'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    AutoScanSchedulerService().stop();
  });
}

TransactionItem _reviewTransaction({
  String type = 'DEBIT',
  String merchantName = 'Original Merchant',
  double amount = 100,
  String categoryId = 'General Expenses',
  String subCategory = 'Miscellaneous',
  double? netPersonalExpense,
  String? accountMask,
  String? referenceNumber,
  String? rawSnippet,
  String? transferCounterpartMask,
}) {
  return TransactionItem(
    id: 'txn-review-00000001',
    amount: amount,
    currency: 'INR',
    type: type,
    merchantName: merchantName,
    accountId: 'acc-1234',
    categoryId: categoryId,
    subCategory: subCategory,
    ingestionSource: 'MANUAL',
    reconciliationStatus: 'NEEDS_REVIEW',
    timestamp: DateTime.utc(2026, 8, 29, 6),
    netPersonalExpense: netPersonalExpense,
    accountMask: accountMask,
    referenceNumber: referenceNumber,
    rawSnippet: rawSnippet,
    transferCounterpartMask: transferCounterpartMask,
  );
}
