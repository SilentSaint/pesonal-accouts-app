class PeerDebtEntry {
  final String id;
  final String contactName;
  final double amount;
  final double settledAmount;
  final String currency;
  final String description;
  final bool isLent; // true if user lent money, false if user borrowed
  final bool isSettled;
  final String? transactionId;
  final DateTime createdAt;
  final DateTime? dueDate;

  PeerDebtEntry({
    required this.id,
    required this.contactName,
    required this.amount,
    this.settledAmount = 0.0,
    required this.currency,
    this.description = '',
    required this.isLent,
    this.isSettled = false,
    this.transactionId,
    required this.createdAt,
    this.dueDate,
  });

  double get remainingAmount => (amount - settledAmount).clamp(0.0, amount);

  PeerDebtEntry copyWith({
    double? settledAmount,
    bool? isSettled,
  }) {
    return PeerDebtEntry(
      id: id,
      contactName: contactName,
      amount: amount,
      settledAmount: settledAmount ?? this.settledAmount,
      currency: currency,
      description: description,
      isLent: isLent,
      isSettled: isSettled ?? this.isSettled,
      transactionId: transactionId,
      createdAt: createdAt,
      dueDate: dueDate,
    );
  }
}

class ContactDebtSummary {
  final String contactName;
  final double netBalance; // positive = user is owed money, negative = user owes money
  final double totalLent;
  final double totalBorrowed;
  final int activeDebtCount;

  ContactDebtSummary({
    required this.contactName,
    required this.netBalance,
    required this.totalLent,
    required this.totalBorrowed,
    required this.activeDebtCount,
  });
}
