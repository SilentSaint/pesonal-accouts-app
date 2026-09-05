class CardEmiPlanItem {
  final String id;
  final String cardAccountId;
  final String cardName;
  final String merchantName;
  final double totalPrincipal;
  final double monthlyInstallment;
  final double interestRatePercent;
  final int totalTenureMonths;
  final int completedInstallments;
  final String currency;
  final DateTime nextDueDate;
  final String status; // ACTIVE, COMPLETED

  CardEmiPlanItem({
    required this.id,
    required this.cardAccountId,
    required this.cardName,
    required this.merchantName,
    required this.totalPrincipal,
    required this.monthlyInstallment,
    required this.interestRatePercent,
    required this.totalTenureMonths,
    required this.completedInstallments,
    required this.currency,
    required this.nextDueDate,
    required this.status,
  });

  int get remainingInstallments => (totalTenureMonths - completedInstallments).clamp(0, totalTenureMonths);
  double get progressPercentage => totalTenureMonths > 0 ? (completedInstallments / totalTenureMonths).clamp(0.0, 1.0) : 0.0;
  bool get isCompleted => status == 'COMPLETED';

  CardEmiPlanItem copyWith({
    int? completedInstallments,
    DateTime? nextDueDate,
    String? status,
  }) {
    return CardEmiPlanItem(
      id: id,
      cardAccountId: cardAccountId,
      cardName: cardName,
      merchantName: merchantName,
      totalPrincipal: totalPrincipal,
      monthlyInstallment: monthlyInstallment,
      interestRatePercent: interestRatePercent,
      totalTenureMonths: totalTenureMonths,
      completedInstallments: completedInstallments ?? this.completedInstallments,
      currency: currency,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      status: status ?? this.status,
    );
  }
}
