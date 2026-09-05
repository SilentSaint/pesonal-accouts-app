class BillStatementItem {
  final String id;
  final String cardAccountId;
  final String cardName;
  final double totalAmount;
  final double minimumDue;
  final double paidAmount;
  final DateTime statementDate;
  final DateTime dueDate;
  final String status; // PENDING, PAID, OVERDUE

  BillStatementItem({
    required this.id,
    required this.cardAccountId,
    required this.cardName,
    required this.totalAmount,
    required this.minimumDue,
    this.paidAmount = 0.0,
    required this.statementDate,
    required this.dueDate,
    required this.status,
  });

  double get remainingDue => (totalAmount - paidAmount).clamp(0.0, totalAmount);
  bool get isPaid => status == 'PAID' || paidAmount >= totalAmount;
  int get daysUntilDue => dueDate.difference(DateTime.now()).inDays;
  bool get isOverdue => !isPaid && DateTime.now().isAfter(dueDate);

  BillStatementItem copyWith({
    double? paidAmount,
    String? status,
  }) {
    return BillStatementItem(
      id: id,
      cardAccountId: cardAccountId,
      cardName: cardName,
      totalAmount: totalAmount,
      minimumDue: minimumDue,
      paidAmount: paidAmount ?? this.paidAmount,
      statementDate: statementDate,
      dueDate: dueDate,
      status: status ?? this.status,
    );
  }
}
