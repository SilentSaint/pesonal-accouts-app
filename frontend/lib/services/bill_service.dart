import 'package:flutter/foundation.dart';
import '../domain/bill_statement.dart';

class BillState extends ChangeNotifier {
  static final BillState _instance = BillState._internal();
  factory BillState() => _instance;
  BillState._internal();

  final List<BillStatementItem> _bills = [];

  List<BillStatementItem> get bills => List.unmodifiable(_bills);
  List<BillStatementItem> get pendingBills => _bills.where((b) => !b.isPaid).toList();

  double get totalPendingBillAmount {
    double sum = 0.0;
    for (final b in pendingBills) {
      sum += b.remainingDue;
    }
    return sum;
  }

  void registerBill({
    required String cardAccountId,
    required String cardName,
    required double totalAmount,
    required double minimumDue,
    required DateTime statementDate,
    required DateTime dueDate,
  }) {
    final bill = BillStatementItem(
      id: 'bill-${DateTime.now().millisecondsSinceEpoch}',
      cardAccountId: cardAccountId,
      cardName: cardName,
      totalAmount: totalAmount,
      minimumDue: minimumDue,
      paidAmount: 0.0,
      statementDate: statementDate,
      dueDate: dueDate,
      status: 'PENDING',
    );
    _bills.insert(0, bill);
    notifyListeners();
  }

  void recordPayment(String billId, [double? amount]) {
    final idx = _bills.indexWhere((b) => b.id == billId);
    if (idx == -1) return;

    final existing = _bills[idx];
    final payment = amount ?? existing.remainingDue;
    final newPaid = existing.paidAmount + payment;
    final isFullyPaid = newPaid >= (existing.totalAmount - 0.01);

    _bills[idx] = existing.copyWith(
      paidAmount: newPaid,
      status: isFullyPaid ? 'PAID' : 'PENDING',
    );
    notifyListeners();
  }
}
