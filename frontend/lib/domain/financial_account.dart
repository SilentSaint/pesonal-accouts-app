class FinancialAccount {
  final String id;
  final String name;
  final String type;
  final String lastFourDigits;
  final String currency;
  final double currentBalance;

  FinancialAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.lastFourDigits,
    required this.currency,
    required this.currentBalance,
  });
}
