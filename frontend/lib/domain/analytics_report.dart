import 'transaction_item.dart';

class AnalyticsReport {
  const AnalyticsReport({
    required this.month,
    required this.currency,
    required this.transactionCount,
    required this.cashFlow,
    required this.categoryTotals,
    required this.spendingTrend,
    required this.aiInsights,
    required this.insightSource,
    this.isSpendingAnalytics = false,
    this.asOf,
    this.formulaId,
    this.formulaVersion,
    this.warnings = const [],
  });

  final String month;
  final String currency;
  final int transactionCount;
  final CashFlow cashFlow;
  final List<CategoryTotal> categoryTotals;
  final List<DailySpendingTrend> spendingTrend;
  final List<String> aiInsights;
  final String insightSource;
  final bool isSpendingAnalytics;
  final String? asOf;
  final String? formulaId;
  final String? formulaVersion;
  final List<String> warnings;

  factory AnalyticsReport.fromJson(Map<String, dynamic> json) {
    if (json['value'] is Map && json['formula'] is Map) {
      return AnalyticsReport._fromIntelligenceJson(json);
    }
    final cashFlow = json['cashFlow'];
    return AnalyticsReport(
      month: json['month'] as String? ?? '',
      currency: json['currency'] as String? ?? 'INR',
      transactionCount: (json['transactionCount'] as num?)?.toInt() ?? 0,
      cashFlow: CashFlow.fromJson(
        cashFlow is Map ? Map<String, dynamic>.from(cashFlow) : const {},
      ),
      categoryTotals: _maps(json['categoryTotals'])
          .map(CategoryTotal.fromJson)
          .toList(growable: false),
      spendingTrend: _maps(json['spendingTrend'])
          .map(DailySpendingTrend.fromJson)
          .toList(growable: false),
      aiInsights: (json['aiInsights'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      insightSource: json['insightSource'] as String? ?? 'SERVER_DERIVED',
    );
  }

  factory AnalyticsReport._fromIntelligenceJson(Map<String, dynamic> json) {
    final value = Map<String, dynamic>.from(json['value'] as Map);
    final current = Map<String, dynamic>.from(value['currentPeriod'] as Map);
    final formula = Map<String, dynamic>.from(json['formula'] as Map);
    final currency = _currency(current['total']);
    final total = _amount(current['total']);
    final categories = _maps(value['categoryBreakdown'])
        .map((item) => CategoryTotal(
              categoryId: item['key'] as String? ?? 'Uncategorized',
              total: _amount(item['total']),
              percentageOfTotal: total == 0
                  ? 0
                  : (_amount(item['total']) / total) * 100,
            ))
        .toList(growable: false);
    final warnings = (json['warnings'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    return AnalyticsReport(
      month: _month(current['start']),
      currency: currency,
      transactionCount: (current['transactionCount'] as num?)?.toInt() ?? 0,
      cashFlow: CashFlow(
        income: 0,
        spending: total,
        netPersonalExpense: total,
        netSavings: 0,
      ),
      categoryTotals: categories,
      spendingTrend: const [],
      aiInsights: warnings.isEmpty
          ? const ['Personal spending is calculated from canonical ledger evidence.']
          : warnings.map((warning) => warning.replaceAll('_', ' ')).toList(),
      insightSource: json['classification'] as String? ?? 'FACT',
      isSpendingAnalytics: true,
      asOf: json['asOf'] as String?,
      formulaId: formula['id'] as String?,
      formulaVersion: formula['version'] as String?,
      warnings: warnings,
    );
  }

  static List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static double _amount(dynamic money) {
    if (money is! Map) return 0;
    return (money['amount'] as num?)?.toDouble() ?? 0;
  }

  static String _currency(dynamic money) {
    if (money is! Map) return 'INR';
    return money['currency'] as String? ?? 'INR';
  }

  static String _month(dynamic start) {
    final value = start as String? ?? '';
    return value.length >= 7 ? value.substring(0, 7) : '';
  }
}

class AnalyticsEvidencePage {
  const AnalyticsEvidencePage({required this.items, this.nextCursor});

  final List<TransactionItem> items;
  final String? nextCursor;

  factory AnalyticsEvidencePage.fromJson(Map<String, dynamic> json) {
    final value = json['value'];
    if (value is! Map) {
      throw const FormatException('Evidence response is invalid');
    }
    final items = value['items'];
    if (items is! List) {
      throw const FormatException('Evidence items are invalid');
    }
    final cursor = value['nextCursor'];
    if (cursor != null && cursor is! String) {
      throw const FormatException('Evidence cursor is invalid');
    }
    return AnalyticsEvidencePage(
      items: items
          .whereType<Map>()
          .map((item) => TransactionItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      nextCursor: cursor as String?,
    );
  }
}

class CashFlow {
  const CashFlow({
    required this.income,
    required this.spending,
    required this.netPersonalExpense,
    required this.netSavings,
  });

  final double income;
  final double spending;
  final double netPersonalExpense;
  final double netSavings;

  factory CashFlow.fromJson(Map<String, dynamic> json) => CashFlow(
        income: (json['income'] as num?)?.toDouble() ?? 0,
        spending: (json['spending'] as num?)?.toDouble() ?? 0,
        netPersonalExpense:
            (json['netPersonalExpense'] as num?)?.toDouble() ?? 0,
        netSavings: (json['netSavings'] as num?)?.toDouble() ?? 0,
      );
}

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.total,
    required this.percentageOfTotal,
  });

  final String categoryId;
  final double total;
  final double percentageOfTotal;

  factory CategoryTotal.fromJson(Map<String, dynamic> json) => CategoryTotal(
        categoryId: json['categoryId'] as String? ?? 'Uncategorized',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        percentageOfTotal:
            (json['percentageOfTotal'] as num?)?.toDouble() ?? 0,
      );
}

class DailySpendingTrend {
  const DailySpendingTrend({
    required this.date,
    required this.income,
    required this.spending,
    required this.netPersonalExpense,
  });

  final String date;
  final double income;
  final double spending;
  final double netPersonalExpense;

  factory DailySpendingTrend.fromJson(Map<String, dynamic> json) =>
      DailySpendingTrend(
        date: json['date'] as String? ?? '',
        income: (json['income'] as num?)?.toDouble() ?? 0,
        spending: (json['spending'] as num?)?.toDouble() ?? 0,
        netPersonalExpense:
            (json['netPersonalExpense'] as num?)?.toDouble() ?? 0,
      );
}
