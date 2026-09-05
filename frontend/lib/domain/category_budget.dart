class CategoryBudgetItem {
  final String id;
  final String categoryId;
  final String categoryName;
  final String yearMonth;
  final double limitAmount;
  final double currentSpend;
  final String currency;

  CategoryBudgetItem({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.yearMonth,
    required this.limitAmount,
    this.currentSpend = 0.0,
    this.currency = 'INR',
  });

  double get spendPercentage => limitAmount > 0 ? ((currentSpend / limitAmount) * 100).clamp(0.0, 999.0) : 0.0;
  double get progressValue => limitAmount > 0 ? (currentSpend / limitAmount).clamp(0.0, 1.0) : 0.0;
  double get remainingBudget => (limitAmount - currentSpend).clamp(0.0, limitAmount);
  bool get isThreshold80Reached => spendPercentage >= 80.0;
  bool get isThreshold100Reached => spendPercentage >= 100.0;

  CategoryBudgetItem copyWith({
    double? limitAmount,
    double? currentSpend,
  }) {
    return CategoryBudgetItem(
      id: id,
      categoryId: categoryId,
      categoryName: categoryName,
      yearMonth: yearMonth,
      limitAmount: limitAmount ?? this.limitAmount,
      currentSpend: currentSpend ?? this.currentSpend,
      currency: currency,
    );
  }
}
