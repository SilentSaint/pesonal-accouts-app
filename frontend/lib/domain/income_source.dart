class IncomeSource {
  const IncomeSource({
    required this.id,
    required this.name,
    required this.type,
    required this.amount,
    required this.currency,
    required this.cadence,
    required this.effectiveFrom,
    required this.linkedAccountId,
    required this.confirmationStatus,
    required this.sourceTransactionIds,
    this.effectiveTo,
  });

  final String id;
  final String name;
  final String type;
  final String amount;
  final String currency;
  final String cadence;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String linkedAccountId;
  final String confirmationStatus;
  final List<String> sourceTransactionIds;

  bool get isVariable => type == 'VARIABLE';
  bool get isConfirmed => confirmationStatus == 'CONFIRMED';
  bool isStaleAt(DateTime asOf) =>
      effectiveTo != null && effectiveTo!.isBefore(_dateOnly(asOf));

  factory IncomeSource.fromJson(Map<String, dynamic> json) {
    final transactionIds = json['sourceTransactionIds'];
    if (json['id'] is! String ||
        json['name'] is! String ||
        json['type'] is! String ||
        json['amount'] is! String ||
        json['currency'] is! String ||
        json['cadence'] is! String ||
        json['effectiveFrom'] is! String ||
        json['linkedAccountId'] is! String ||
        json['confirmationStatus'] is! String ||
        transactionIds is! List) {
      throw const FormatException('Invalid income source');
    }
    return IncomeSource(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      amount: json['amount'] as String,
      currency: json['currency'] as String,
      cadence: json['cadence'] as String,
      effectiveFrom: _parseDate(json['effectiveFrom'] as String),
      effectiveTo: json['effectiveTo'] == null
          ? null
          : _parseDate(json['effectiveTo'] as String),
      linkedAccountId: json['linkedAccountId'] as String,
      confirmationStatus: json['confirmationStatus'] as String,
      sourceTransactionIds:
          transactionIds.map((id) => id.toString()).toList(growable: false),
    );
  }

  Map<String, dynamic> toRequestJson() => {
        'name': name,
        'type': type,
        'amount': amount,
        'currency': currency,
        'cadence': cadence,
        'effectiveFrom': _formatDate(effectiveFrom),
        if (effectiveTo != null) 'effectiveTo': _formatDate(effectiveTo!),
        'linkedAccountId': linkedAccountId,
        'sourceTransactionIds': sourceTransactionIds,
      };
}

class IncomeSuggestion {
  const IncomeSuggestion({required this.source, required this.confidence});

  final IncomeSource source;
  final double confidence;

  factory IncomeSuggestion.fromJson(Map<String, dynamic> json) {
    if (json['source'] is! Map || json['confidence'] is! num) {
      throw const FormatException('Invalid income suggestion');
    }
    return IncomeSuggestion(
      source: IncomeSource.fromJson(
          Map<String, dynamic>.from(json['source'] as Map)),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }
}

class IncomeSourceList {
  const IncomeSourceList({required this.sources, required this.suggestions});

  final List<IncomeSource> sources;
  final List<IncomeSuggestion> suggestions;

  factory IncomeSourceList.fromJson(Map<String, dynamic> json) {
    if (json['sources'] is! List || json['suggestions'] is! List) {
      throw const FormatException('Invalid income source response');
    }
    return IncomeSourceList(
      sources: (json['sources'] as List)
          .map((source) =>
              IncomeSource.fromJson(Map<String, dynamic>.from(source as Map)))
          .toList(growable: false),
      suggestions: (json['suggestions'] as List)
          .map((suggestion) => IncomeSuggestion.fromJson(
              Map<String, dynamic>.from(suggestion as Map)))
          .toList(growable: false),
    );
  }
}

class IncomeSummary {
  const IncomeSummary({
    required this.periodStart,
    required this.periodEnd,
    required this.asOf,
    required this.currency,
    required this.observed,
    required this.expected,
    required this.uncertain,
    required this.confirmedSourceCount,
    required this.unconfirmedSuggestionCount,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime asOf;
  final String currency;
  final String observed;
  final String expected;
  final String uncertain;
  final int confirmedSourceCount;
  final int unconfirmedSuggestionCount;

  factory IncomeSummary.fromJson(Map<String, dynamic> json) {
    if (json['periodStart'] is! String ||
        json['periodEnd'] is! String ||
        json['asOf'] is! String ||
        json['currency'] is! String ||
        json['observed'] is! String ||
        json['expected'] is! String ||
        json['uncertain'] is! String ||
        json['confirmedSourceCount'] is! int ||
        json['unconfirmedSuggestionCount'] is! int) {
      throw const FormatException('Invalid income summary');
    }
    return IncomeSummary(
      periodStart: _parseDate(json['periodStart'] as String),
      periodEnd: _parseDate(json['periodEnd'] as String),
      asOf: _parseDate(json['asOf'] as String),
      currency: json['currency'] as String,
      observed: json['observed'] as String,
      expected: json['expected'] as String,
      uncertain: json['uncertain'] as String,
      confirmedSourceCount: json['confirmedSourceCount'] as int,
      unconfirmedSuggestionCount: json['unconfirmedSuggestionCount'] as int,
    );
  }
}

DateTime _parseDate(String value) {
  final date = DateTime.parse(value.split('T').first);
  return DateTime.utc(date.year, date.month, date.day);
}

DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

String _formatDate(DateTime value) =>
    _dateOnly(value).toIso8601String().substring(0, 10);
