class ConversationDrillDown {
  const ConversationDrillDown({
    required this.start,
    required this.end,
    required this.currency,
    required this.accountIds,
    this.categoryId,
    this.merchantName,
  });

  final String start;
  final String end;
  final String currency;
  final List<String> accountIds;
  final String? categoryId;
  final String? merchantName;

  factory ConversationDrillDown.fromJson(Map<String, dynamic> json) =>
      ConversationDrillDown(
        start: _requiredString(json, 'start'),
        end: _requiredString(json, 'end'),
        currency: _requiredString(json, 'currency'),
        accountIds: (json['accountIds'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        categoryId: _optionalString(json['categoryId']),
        merchantName: _optionalString(json['merchantName']),
      );
}

class ConversationalFinanceQueryResponse {
  const ConversationalFinanceQueryResponse.answer({
    required this.observation,
    required this.asOf,
    required this.sourceCount,
    this.drillDown,
    bool hasEvidence = false,
  })  : status = ConversationalFinanceQueryStatus.answer,
        clarification = null,
        _hasEvidence = hasEvidence;

  const ConversationalFinanceQueryResponse.clarification(this.clarification)
      : status = ConversationalFinanceQueryStatus.clarification,
        observation = null,
        asOf = null,
        sourceCount = null,
        drillDown = null,
        _hasEvidence = false;

  final ConversationalFinanceQueryStatus status;
  final String? observation;
  final String? clarification;
  final String? asOf;
  final int? sourceCount;
  final ConversationDrillDown? drillDown;
  final bool _hasEvidence;

  bool get hasEvidence => _hasEvidence || drillDown != null;

  factory ConversationalFinanceQueryResponse.fromJson(
      Map<String, dynamic> json) {
    switch (json['status']) {
      case 'ANSWER':
        final drillDown = json['drillDown'];
        return ConversationalFinanceQueryResponse.answer(
          observation: _requiredString(json, 'observation'),
          asOf: _requiredString(json, 'asOf'),
          sourceCount: (json['sourceCount'] as num?)?.toInt() ??
              (throw const FormatException('sourceCount is invalid')),
          drillDown: drillDown is Map
              ? ConversationDrillDown.fromJson(
                  Map<String, dynamic>.from(drillDown))
              : null,
        );
      case 'CLARIFICATION':
        return ConversationalFinanceQueryResponse.clarification(
            _requiredString(json, 'message'));
      default:
        throw const FormatException('Conversational query response is invalid');
    }
  }
}

enum ConversationalFinanceQueryStatus { answer, clarification }

String _requiredString(Map<String, dynamic> value, String field) {
  final result = value[field];
  if (result is! String || result.isEmpty) {
    throw FormatException('$field is invalid');
  }
  return result;
}

String? _optionalString(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return value;
}
