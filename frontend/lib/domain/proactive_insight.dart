class InsightMoney {
  const InsightMoney({required this.amount, required this.currency});

  final double amount;
  final String currency;

  factory InsightMoney.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Insight amount is invalid');
    final amount = json['amount'];
    final currency = json['currency'];
    if (amount is! num || currency is! String) {
      throw const FormatException('Insight amount is invalid');
    }
    return InsightMoney(amount: amount.toDouble(), currency: currency);
  }
}

class InsightTransaction {
  const InsightTransaction({
    required this.transactionId,
    required this.merchantName,
    required this.personalSpend,
  });

  final String transactionId;
  final String merchantName;
  final double personalSpend;

  factory InsightTransaction.fromJson(Object? json) {
    if (json is! Map ||
        json['transactionId'] is! String ||
        json['merchantName'] is! String ||
        json['personalSpend'] is! Map) {
      throw const FormatException('Insight transaction is invalid');
    }
    return InsightTransaction(
      transactionId: json['transactionId'] as String,
      merchantName: json['merchantName'] as String,
      personalSpend:
          ((json['personalSpend'] as Map)['amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ProactiveInsight {
  const ProactiveInsight({
    required this.id,
    required this.type,
    required this.classification,
    required this.title,
    required this.message,
    required this.currentAmount,
    required this.baselineAmount,
    required this.baselineLabel,
    required this.confidence,
    required this.freshnessAsOf,
    required this.matchingTransactions,
  });

  final String id;
  final String type;
  final String classification;
  final String title;
  final String message;
  final InsightMoney currentAmount;
  final InsightMoney baselineAmount;
  final String baselineLabel;
  final double confidence;
  final String freshnessAsOf;
  final List<InsightTransaction> matchingTransactions;

  factory ProactiveInsight.fromJson(Object? json) {
    if (json is! Map ||
        json['id'] is! String ||
        json['title'] is! String ||
        json['message'] is! String ||
        json['classification'] is! String ||
        json['type'] is! String ||
        json['confidence'] is! num ||
        json['freshnessAsOf'] is! String) {
      throw const FormatException('Insight card is invalid');
    }
    final baseline = json['comparisonBaseline'];
    if (baseline is! Map || baseline['label'] is! String) {
      throw const FormatException('Insight baseline is invalid');
    }
    final transactions = json['matchingTransactions'];
    if (transactions is! List) {
      throw const FormatException('Insight evidence is invalid');
    }
    return ProactiveInsight(
      id: json['id'] as String,
      type: json['type'] as String,
      classification: json['classification'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      currentAmount: InsightMoney.fromJson(json['currentAmount']),
      baselineAmount: InsightMoney.fromJson(baseline['amount']),
      baselineLabel: baseline['label'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      freshnessAsOf: json['freshnessAsOf'] as String,
      matchingTransactions:
          transactions.map(InsightTransaction.fromJson).toList(growable: false),
    );
  }
}
