class TransactionItem {
  final String id;
  final double amount;
  final String currency;
  final String type; // DEBIT or CREDIT or TRANSFER
  final String merchantName;
  final String accountId;
  final String? categoryId;
  final String? subCategory; // e.g. "Tea & Snacks"
  final String ingestionSource; // SMS, EMAIL, MANUAL
  final List<String> ingestionSources; // Canonical evidence channels
  final String reconciliationStatus; // CONFIRMED, NEEDS_REVIEW, AUTO_MERGED
  final String? potentialDuplicateOfTransactionId;
  final DateTime timestamp;
  final double? netPersonalExpense;
  final String? accountMask; // e.g. "•••• 1277"
  final String?
      referenceNumber; // e.g. "paytm.s1yxlpq@pty" or "UPI Ref: 4234..."
  final String? rawSnippet; // Context snippet from the bank notification
  /// For self-transfers: the other leg's account mask (e.g. debit leg stores "•••• 9343" = destination)
  final String? transferCounterpartMask;

  TransactionItem({
    required this.id,
    required this.amount,
    required this.currency,
    required this.type,
    required this.merchantName,
    required this.accountId,
    this.categoryId,
    this.subCategory,
    required this.ingestionSource,
    this.ingestionSources = const [],
    required this.reconciliationStatus,
    this.potentialDuplicateOfTransactionId,
    required this.timestamp,
    this.netPersonalExpense,
    this.accountMask,
    this.referenceNumber,
    this.rawSnippet,
    this.transferCounterpartMask,
  });

  TransactionItem copyWith({
    String? id,
    double? amount,
    String? currency,
    String? type,
    String? merchantName,
    String? accountId,
    String? categoryId,
    String? subCategory,
    String? ingestionSource,
    List<String>? ingestionSources,
    String? reconciliationStatus,
    String? potentialDuplicateOfTransactionId,
    DateTime? timestamp,
    double? netPersonalExpense,
    String? accountMask,
    String? referenceNumber,
    String? rawSnippet,
    String? transferCounterpartMask,
  }) {
    return TransactionItem(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      type: type ?? this.type,
      merchantName: merchantName ?? this.merchantName,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      subCategory: subCategory ?? this.subCategory,
      ingestionSource: ingestionSource ?? this.ingestionSource,
      ingestionSources: ingestionSources ?? this.ingestionSources,
      reconciliationStatus: reconciliationStatus ?? this.reconciliationStatus,
      potentialDuplicateOfTransactionId: potentialDuplicateOfTransactionId ??
          this.potentialDuplicateOfTransactionId,
      timestamp: timestamp ?? this.timestamp,
      netPersonalExpense: netPersonalExpense ?? this.netPersonalExpense,
      accountMask: accountMask ?? this.accountMask,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      rawSnippet: rawSnippet ?? this.rawSnippet,
      transferCounterpartMask:
          transferCounterpartMask ?? this.transferCounterpartMask,
    );
  }

  bool get needsReview =>
      reconciliationStatus == 'NEEDS_REVIEW' || categoryId == null;
  bool get isTransfer =>
      type == 'TRANSFER' ||
      categoryId == 'Self Transfer' ||
      categoryId == 'Transfer';
  double get effectivePersonalExpense =>
      isTransfer ? 0.0 : (netPersonalExpense ?? amount);

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'currency': currency,
        'type': type,
        'merchantName': merchantName,
        'accountId': accountId,
        'categoryId': categoryId,
        'subCategory': subCategory,
        'ingestionSource': ingestionSource,
        'ingestionSources': ingestionSources,
        'reconciliationStatus': reconciliationStatus,
        'potentialDuplicateOfTransactionId': potentialDuplicateOfTransactionId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'netPersonalExpense': netPersonalExpense,
        'accountMask': accountMask,
        'referenceNumber': referenceNumber,
        'rawSnippet': rawSnippet,
        'transferCounterpartMask': transferCounterpartMask,
      };

  factory TransactionItem.fromJson(Map<String, dynamic> json) =>
      TransactionItem(
        id: json['id'] ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        currency: json['currency'] ?? 'INR',
        type: json['type'] ?? 'DEBIT',
        merchantName: json['merchantName'] ?? '',
        accountId: json['accountId'] ?? '',
        categoryId: json['categoryId'],
        subCategory: json['subCategory'] as String?,
        ingestionSource: json['ingestionSource'] ?? 'MANUAL',
        ingestionSources:
            (json['ingestionSources'] as List?)?.whereType<String>().toList() ??
                const [],
        reconciliationStatus: json['reconciliationStatus'] ?? 'CONFIRMED',
        potentialDuplicateOfTransactionId:
            json['potentialDuplicateOfTransactionId'] as String?,
        timestamp: json['timestamp'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
            : (json['timestamp'] is String
                ? (DateTime.tryParse(json['timestamp'] as String) ??
                    DateTime.now())
                : DateTime.now()),
        netPersonalExpense: (json['netPersonalExpense'] as num?)?.toDouble(),
        accountMask: json['accountMask'] as String?,
        referenceNumber: json['referenceNumber'] as String?,
        rawSnippet: json['rawSnippet'] as String?,
        transferCounterpartMask: json['transferCounterpartMask'] as String?,
      );
}
