import 'package:flutter/foundation.dart';
import '../domain/loan_account.dart';

class LoanState extends ChangeNotifier {
  static final LoanState _instance = LoanState._internal();
  factory LoanState() => _instance;
  LoanState._internal();

  final List<LoanAccountItem> _loans = [];

  List<LoanAccountItem> get loans => List.unmodifiable(_loans);
  List<LoanAccountItem> get activeLoans => _loans.where((l) => !l.isClosed).toList();

  void registerLoan({
    required String loanName,
    required String lenderName,
    required double principalAmount,
    required double emiAmount,
    required double interestRatePercent,
    required int totalInstallments,
    required DateTime nextDueDate,
    String currency = 'INR',
  }) {
    final loan = LoanAccountItem(
      id: 'loan-${DateTime.now().millisecondsSinceEpoch}',
      loanName: loanName.trim(),
      lenderName: lenderName.trim(),
      principalAmount: principalAmount,
      remainingPrincipal: principalAmount,
      emiAmount: emiAmount,
      interestRatePercent: interestRatePercent,
      totalInstallments: totalInstallments,
      completedInstallments: 0,
      currency: currency,
      nextDueDate: nextDueDate,
      status: 'ACTIVE',
    );
    _loans.insert(0, loan);
    notifyListeners();
  }

  void recordEmiPayment(String loanId, [double? amount]) {
    final idx = _loans.indexWhere((l) => l.id == loanId);
    if (idx == -1) return;

    final existing = _loans[idx];
    final payment = amount ?? existing.emiAmount;
    final newRemaining = (existing.remainingPrincipal - payment).clamp(0.0, double.infinity);
    final newCompleted = existing.completedInstallments + 1;
    final isClosed = newRemaining <= 0 || newCompleted >= existing.totalInstallments;

    _loans[idx] = existing.copyWith(
      remainingPrincipal: newRemaining,
      completedInstallments: newCompleted,
      status: isClosed ? 'CLOSED' : 'ACTIVE',
      nextDueDate: DateTime(existing.nextDueDate.year, existing.nextDueDate.month + 1, existing.nextDueDate.day),
    );
    notifyListeners();
  }
}
