import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:automatic_expense_tracker/domain/transaction_item.dart';
import 'package:automatic_expense_tracker/ui/transaction_review_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Duplicate Detection & Merge Tests', () {
    testWidgets(
        'Distinct payments with different UPI refs or dates do NOT show 1-Tap Merge',
        (WidgetTester tester) async {
      final distinctPending = [
        TransactionItem(
          id: 'txn-1',
          amount: 25.0,
          currency: 'INR',
          type: 'DEBIT',
          merchantName: 'Chai Works',
          accountId: 'acc-gmail',
          categoryId: 'Food & Dining',
          subCategory: 'Tea & Snacks',
          ingestionSource: 'EMAIL',
          reconciliationStatus: 'NEEDS_REVIEW',
          timestamp: DateTime(2026, 8, 27, 14, 29),
          referenceNumber: '660599700199',
          rawSnippet:
              'Dear Customer, Greetings from HDFC Bank! Rs.25.00 is debited from your account ending 1277 towards VPA paytm.s1yxlpq@pty (Saira Banu) on 27-08-26. UPI transaction reference no.: 660599700199.',
        ),
        TransactionItem(
          id: 'txn-2',
          amount: 25.0,
          currency: 'INR',
          type: 'DEBIT',
          merchantName: 'Saira Banu',
          accountId: 'acc-gmail',
          categoryId: 'General Expenses',
          ingestionSource: 'EMAIL',
          reconciliationStatus: 'NEEDS_REVIEW',
          timestamp: DateTime(2026, 8, 26, 14, 29),
          referenceNumber: '623830330403',
          rawSnippet:
              'Dear Customer, Greetings from HDFC Bank! Rs.25.00 is debited from your account ending 1277 towards VPA paytm.s1yxlpq@pty (Saira Banu) on 26-08-26. UPI transaction reference no.: 623830330403.',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionReviewModal(
              pendingTransactions: distinctPending,
              onConfirm: (item, cat) => true,
              onMerge: (target, dup) {},
              onDismiss: (item) {},
            ),
          ),
        ),
      );

      // Neither card should show "Potential Duplicate"
      expect(find.text('Potential Duplicate'), findsNothing);
      // Both cards should show "Needs Review"
      expect(find.text('Needs Review'), findsNWidgets(2));
      // "1-Tap Merge" button must NOT appear when there are no duplicates to merge
      expect(find.text('1-Tap Merge'), findsNothing);
      // Both cards should show "Confirm Expense"
      expect(find.text('Confirm Expense'), findsNWidgets(2));
    });

    testWidgets(
        'True duplicate with identical UPI ref shows 1-Tap Merge and Duplicate badge',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final duplicatePending = [
        TransactionItem(
          id: 'txn-sms',
          amount: 25.0,
          currency: 'INR',
          type: 'DEBIT',
          merchantName: 'Saira Banu',
          accountId: 'acc-sms',
          categoryId: 'Food & Dining',
          ingestionSource: 'SMS',
          reconciliationStatus: 'NEEDS_REVIEW',
          timestamp: DateTime(2026, 8, 27, 14, 05),
          referenceNumber: '660599700199',
          rawSnippet: 'Paid Rs.25 to Saira Banu via UPI Ref 660599700199',
        ),
        TransactionItem(
          id: 'txn-email',
          amount: 25.0,
          currency: 'INR',
          type: 'DEBIT',
          merchantName: 'Chai Works',
          accountId: 'acc-gmail',
          categoryId: 'Food & Dining',
          ingestionSource: 'EMAIL',
          reconciliationStatus: 'NEEDS_REVIEW',
          potentialDuplicateOfTransactionId: 'txn-sms',
          timestamp: DateTime(2026, 8, 27, 14, 06),
          referenceNumber: '660599700199',
          rawSnippet:
              'Rs.25.00 debited from account 1277 towards VPA paytm.s1yxlpq@pty on 27-08-26. UPI transaction reference no.: 660599700199.',
        ),
      ];

      TransactionItem? mergedTarget;
      TransactionItem? mergedDuplicate;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionReviewModal(
              pendingTransactions: duplicatePending,
              onConfirm: (item, cat) => true,
              onMerge: (target, dup) {
                mergedTarget = target;
                mergedDuplicate = dup;
              },
              onDismiss: (item) {},
            ),
          ),
        ),
      );

      // Duplicate badges should be present
      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
      // 1-Tap Merge button should appear for duplicate
      expect(find.text('1-Tap Merge'), findsWidgets);

      // Tap 1-Tap Merge on the first card
      final mergeButton = find.text('1-Tap Merge').first;
      await tester.ensureVisible(mergeButton);
      await tester.tap(mergeButton);
      await tester.pumpAndSettle();

      // Ensure the merge callback received both target and duplicate
      expect(mergedTarget, isNotNull);
      expect(mergedDuplicate, isNotNull);
      expect(mergedTarget!.id, 'txn-sms');
      expect(mergedDuplicate!.id, 'txn-email');
    });
  });
}
