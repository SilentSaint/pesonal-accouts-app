import 'package:flutter/foundation.dart';
import '../domain/category_budget.dart';

class BudgetState extends ChangeNotifier {
  static final BudgetState _instance = BudgetState._internal();
  factory BudgetState() => _instance;
  BudgetState._internal();

  final List<CategoryBudgetItem> _budgets = [];

  List<CategoryBudgetItem> get budgets => List.unmodifiable(_budgets);

  List<CategoryBudgetItem> getBudgetsForMonth(String yearMonth) {
    return _budgets.where((b) => b.yearMonth == yearMonth).toList();
  }

  void setBudget({
    required String categoryId,
    required String categoryName,
    required String yearMonth,
    required double limitAmount,
  }) {
    final index = _budgets.indexWhere((b) => b.categoryId == categoryId && b.yearMonth == yearMonth);
    if (index != -1) {
      _budgets[index] = _budgets[index].copyWith(limitAmount: limitAmount);
    } else {
      _budgets.add(
        CategoryBudgetItem(
          id: 'b-${DateTime.now().millisecondsSinceEpoch}',
          categoryId: categoryId,
          categoryName: categoryName,
          yearMonth: yearMonth,
          limitAmount: limitAmount,
          currentSpend: 0.0,
        ),
      );
    }
    notifyListeners();
  }

  void updateSpend({
    required String categoryId,
    required String yearMonth,
    required double additionalSpend,
  }) {
    final index = _budgets.indexWhere((b) => b.categoryId == categoryId && b.yearMonth == yearMonth);
    if (index != -1) {
      final updated = _budgets[index].currentSpend + additionalSpend;
      _budgets[index] = _budgets[index].copyWith(currentSpend: updated);
      notifyListeners();
    }
  }
}
