class FinancialAccount {
  final String id;
  final String name;
  final String type; // 'SAVINGS', 'CREDIT_CARD', 'LOAN', 'INVESTMENT'
  final String lastFourDigits;
  final String currency;
  final double currentBalance;
  // Loan tracking specific fields
  final double? emiAmount;
  final double? principalAmount;
  final double? interestRatePercent;
  final int? totalInstallments;
  final int? completedInstallments;
  final String? lenderName;
  final String? nextDueDate;

  final double? anchorBalance;
  final DateTime? anchorDate;

  FinancialAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.lastFourDigits,
    required this.currency,
    required this.currentBalance,
    this.emiAmount,
    this.principalAmount,
    this.interestRatePercent,
    this.totalInstallments,
    this.completedInstallments,
    this.lenderName,
    this.nextDueDate,
    this.anchorBalance,
    this.anchorDate,
  });

  bool get isCreditCard => type == 'CREDIT_CARD';
  bool get isSavings => type == 'SAVINGS';
  bool get isLoan => type == 'LOAN';

  FinancialAccount copyWith({
    String? id,
    String? name,
    String? type,
    String? lastFourDigits,
    String? currency,
    double? currentBalance,
    double? emiAmount,
    double? principalAmount,
    double? interestRatePercent,
    int? totalInstallments,
    int? completedInstallments,
    String? lenderName,
    String? nextDueDate,
    double? anchorBalance,
    DateTime? anchorDate,
  }) {
    return FinancialAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      lastFourDigits: lastFourDigits ?? this.lastFourDigits,
      currency: currency ?? this.currency,
      currentBalance: currentBalance ?? this.currentBalance,
      emiAmount: emiAmount ?? this.emiAmount,
      principalAmount: principalAmount ?? this.principalAmount,
      interestRatePercent: interestRatePercent ?? this.interestRatePercent,
      totalInstallments: totalInstallments ?? this.totalInstallments,
      completedInstallments: completedInstallments ?? this.completedInstallments,
      lenderName: lenderName ?? this.lenderName,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      anchorBalance: anchorBalance ?? this.anchorBalance,
      anchorDate: anchorDate ?? this.anchorDate,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'lastFourDigits': lastFourDigits,
    'currency': currency,
    'currentBalance': currentBalance,
    if (emiAmount != null) 'emiAmount': emiAmount,
    if (principalAmount != null) 'principalAmount': principalAmount,
    if (interestRatePercent != null) 'interestRatePercent': interestRatePercent,
    if (totalInstallments != null) 'totalInstallments': totalInstallments,
    if (completedInstallments != null) 'completedInstallments': completedInstallments,
    if (lenderName != null) 'lenderName': lenderName,
    if (nextDueDate != null) 'nextDueDate': nextDueDate,
    if (anchorBalance != null) 'anchorBalance': anchorBalance,
    if (anchorDate != null) 'anchorDate': anchorDate!.toIso8601String(),
  };

  factory FinancialAccount.fromJson(Map<String, dynamic> json) => FinancialAccount(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    type: json['type'] ?? 'SAVINGS',
    lastFourDigits: json['lastFourDigits'] ?? '0000',
    currency: json['currency'] ?? 'INR',
    currentBalance: (json['currentBalance'] ?? 0.0).toDouble(),
    emiAmount: json['emiAmount'] != null ? (json['emiAmount'] as num).toDouble() : null,
    principalAmount: json['principalAmount'] != null ? (json['principalAmount'] as num).toDouble() : null,
    interestRatePercent: json['interestRatePercent'] != null ? (json['interestRatePercent'] as num).toDouble() : null,
    totalInstallments: json['totalInstallments'],
    completedInstallments: json['completedInstallments'],
    lenderName: json['lenderName'],
    nextDueDate: json['nextDueDate'],
    anchorBalance: json['anchorBalance'] != null ? (json['anchorBalance'] as num).toDouble() : null,
    anchorDate: json['anchorDate'] != null ? DateTime.tryParse(json['anchorDate'].toString()) : null,
  );
}
