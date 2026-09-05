class RecurringCommitment {
  const RecurringCommitment({
    required this.id,
    required this.name,
    required this.classification,
    required this.cadence,
    required this.minimumAmount,
    required this.maximumAmount,
    required this.currency,
    required this.nextPaymentDate,
    required this.confidence,
    required this.supportingTransactionIds,
    required this.status,
    required this.state,
    required this.origin,
    this.authoritativeReference,
  });

  final String id;
  final String name;
  final String classification;
  final String cadence;
  final String minimumAmount;
  final String maximumAmount;
  final String currency;
  final DateTime nextPaymentDate;
  final double confidence;
  final List<String> supportingTransactionIds;
  final String status;
  final String state;
  final String origin;
  final String? authoritativeReference;

  bool get isCandidate => status == 'CANDIDATE';
  bool get isConfirmed => status == 'CONFIRMED';
  bool get isVariableAmount => state == 'VARIABLE_AMOUNT';
  bool get isAuthoritative => origin != 'DETECTED';

  factory RecurringCommitment.fromJson(Map<String, dynamic> json) {
    final evidence = json['supportingTransactionIds'];
    if (json['id'] is! String ||
        json['name'] is! String ||
        json['classification'] is! String ||
        json['cadence'] is! String ||
        json['minimumAmount'] is! String ||
        json['maximumAmount'] is! String ||
        json['currency'] is! String ||
        json['nextPaymentDate'] is! String ||
        json['confidence'] is! num ||
        evidence is! List ||
        json['status'] is! String ||
        json['state'] is! String ||
        json['origin'] is! String) {
      throw const FormatException('Invalid recurring commitment');
    }
    return RecurringCommitment(
      id: json['id'] as String,
      name: json['name'] as String,
      classification: json['classification'] as String,
      cadence: json['cadence'] as String,
      minimumAmount: json['minimumAmount'] as String,
      maximumAmount: json['maximumAmount'] as String,
      currency: json['currency'] as String,
      nextPaymentDate: _parseDate(json['nextPaymentDate'] as String),
      confidence: (json['confidence'] as num).toDouble(),
      supportingTransactionIds:
          evidence.map((value) => value.toString()).toList(growable: false),
      status: json['status'] as String,
      state: json['state'] as String,
      origin: json['origin'] as String,
      authoritativeReference: json['authoritativeReference'] as String?,
    );
  }

  Map<String, dynamic> toRequestJson() => {
        'name': name,
        'classification': classification,
        'cadence': cadence,
        'minimumAmount': minimumAmount,
        'maximumAmount': maximumAmount,
        'currency': currency,
        'nextPaymentDate': _formatDate(nextPaymentDate),
      };
}

class RecurringCommitmentList {
  const RecurringCommitmentList(
      {required this.asOf, required this.commitments});

  final DateTime asOf;
  final List<RecurringCommitment> commitments;

  factory RecurringCommitmentList.fromJson(Map<String, dynamic> json) {
    if (json['asOf'] is! String || json['commitments'] is! List) {
      throw const FormatException('Invalid recurring commitments response');
    }
    return RecurringCommitmentList(
      asOf: _parseDate(json['asOf'] as String),
      commitments: (json['commitments'] as List)
          .map((item) => RecurringCommitment.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
    );
  }
}

DateTime _parseDate(String value) {
  final date = DateTime.parse(value.split('T').first);
  return DateTime.utc(date.year, date.month, date.day);
}

String _formatDate(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day)
        .toIso8601String()
        .substring(0, 10);
