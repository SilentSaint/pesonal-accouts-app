import 'package:automatic_expense_tracker/domain/review_payee_identity.dart';
import 'package:automatic_expense_tracker/domain/transaction_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches exact VPA case-insensitively', () {
    expect(ReviewPayeeIdentity.matches(_txn('A', 'Shop', 'a@upi'),
        _txn('B', 'Other', 'A@UPI')), isTrue);
  });

  test('does not match different VPAs on the same platform', () {
    expect(ReviewPayeeIdentity.matches(_txn('A', 'Shop', 'a@upi'),
        _txn('B', 'Shop', 'b@upi')), isFalse);
  });

  test('matches normalized merchants when no VPA exists', () {
    expect(ReviewPayeeIdentity.matches(_txn('A', ' Green  Market ', null),
        _txn('B', 'green market', null)), isTrue);
    expect(ReviewPayeeIdentity.matches(_txn('A', 'Bank Alert', null),
        _txn('B', 'Bank Alert', null)), isFalse);
  });
}

TransactionItem _txn(String id, String merchant, String? vpa) => TransactionItem(
      id: id,
      amount: 100,
      currency: 'INR',
      type: 'DEBIT',
      merchantName: merchant,
      accountId: 'account',
      ingestionSource: 'EMAIL',
      reconciliationStatus: 'NEEDS_REVIEW',
      timestamp: DateTime.utc(2026, 9, 5),
      referenceNumber: 'ref-$id',
      rawSnippet: vpa == null ? null : 'Debited towards VPA $vpa ($merchant)',
    );
