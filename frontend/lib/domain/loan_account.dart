class LoanAccountItem {
  final String id;
  final String loanName;
  final String lenderName;
  final double principalAmount;
  final double remainingPrincipal;
  final double emiAmount;
  final double interestRatePercent;
  final int totalInstallments;
  final int completedInstallments;
  final String currency;
  final DateTime nextDueDate;
  final String status; // ACTIVE, CLOSED

  LoanAccountItem({
    required this.id,
    required this.loanName,
    required this.lenderName,
    required this.principalAmount,
    required this.remainingPrincipal,
    required this.emiAmount,
    required this.interestRatePercent,
    required this.totalInstallments,
    required this.completedInstallments,
    required this.currency,
    required this.nextDueDate,
    required this.status,
  });

  int get remainingInstallments => (totalInstallments - completedInstallments).clamp(0, totalInstallments);
  double get progressPercentage => totalInstallments > 0 ? (completedInstallments / totalInstallments).clamp(0.0, 1.0) : 0.0;
  bool get isClosed => status == 'CLOSED';

  LoanAccountItem copyWith({
    double? remainingPrincipal,
    int? completedInstallments,
    DateTime? nextDueDate,
    String? status,
  }) {
    return LoanAccountItem(
      id: id,
      loanName: loanName,
      lenderName: lenderName,
      principalAmount: principalAmount,
      remainingPrincipal: remainingPrincipal ?? this.remainingPrincipal,
      emiAmount: emiAmount,
      interestRatePercent: interestRatePercent,
      totalInstallments: totalInstallments,
      completedInstallments: completedInstallments ?? this.completedInstallments,
      currency: currency,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      status: status ?? this.status,
    );
  }
}
