import 'package:flutter/foundation.dart';
import '../domain/card_emi_plan.dart';

class CardEmiState extends ChangeNotifier {
  static final CardEmiState _instance = CardEmiState._internal();
  factory CardEmiState() => _instance;
  CardEmiState._internal();

  final List<CardEmiPlanItem> _plans = [];

  List<CardEmiPlanItem> get plans => List.unmodifiable(_plans);
  List<CardEmiPlanItem> get activePlans => _plans.where((p) => !p.isCompleted).toList();

  double get totalMonthlyCommittedEmi {
    double sum = 0.0;
    for (final p in activePlans) {
      sum += p.monthlyInstallment;
    }
    return sum;
  }

  void convertToEmi({
    required String cardAccountId,
    required String cardName,
    required String merchantName,
    required double totalAmount,
    required double monthlyInstallment,
    required double interestRatePercent,
    required int tenureMonths,
    required DateTime nextDueDate,
    String? originalTransactionId,
  }) {
    final plan = CardEmiPlanItem(
      id: 'emi-${DateTime.now().millisecondsSinceEpoch}',
      cardAccountId: cardAccountId,
      cardName: cardName,
      merchantName: merchantName,
      totalPrincipal: totalAmount,
      monthlyInstallment: monthlyInstallment,
      interestRatePercent: interestRatePercent,
      totalTenureMonths: tenureMonths,
      completedInstallments: 0,
      currency: 'INR',
      nextDueDate: nextDueDate,
      status: 'ACTIVE',
    );
    _plans.insert(0, plan);
    notifyListeners();
  }

  void recordInstallmentPaid(String emiId) {
    final idx = _plans.indexWhere((p) => p.id == emiId);
    if (idx == -1) return;

    final existing = _plans[idx];
    final newCompleted = existing.completedInstallments + 1;
    final isDone = newCompleted >= existing.totalTenureMonths;

    _plans[idx] = existing.copyWith(
      completedInstallments: newCompleted,
      status: isDone ? 'COMPLETED' : 'ACTIVE',
      nextDueDate: DateTime(existing.nextDueDate.year, existing.nextDueDate.month + 1, existing.nextDueDate.day),
    );
    notifyListeners();
  }
}
