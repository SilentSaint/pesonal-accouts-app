class FinancialContextItem {
  const FinancialContextItem({
    required this.id,
    required this.type,
    required this.label,
    required this.values,
    required this.capabilities,
    required this.provenance,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
    this.effectiveFrom,
    this.effectiveUntil,
    this.status = 'ACTIVE',
    this.conflictIds = const [],
  });

  final String id;
  final String type;
  final String label;
  final Map<String, String> values;
  final List<String> capabilities;
  final String provenance;
  final DateTime? effectiveFrom;
  final DateTime? effectiveUntil;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String status;
  final List<String> conflictIds;

  bool get isEligible => status == 'ACTIVE';

  factory FinancialContextItem.fromJson(Map<String, dynamic> json) {
    final values = json['values'];
    final capabilities = json['capabilities'];
    if (json['id'] is! String ||
        json['type'] is! String ||
        json['label'] is! String ||
        values is! Map ||
        capabilities is! List ||
        json['provenance'] is! String ||
        json['active'] is! bool ||
        json['createdAt'] is! String ||
        json['updatedAt'] is! String) {
      throw const FormatException('Invalid financial context item');
    }
    return FinancialContextItem(
      id: json['id'] as String,
      type: json['type'] as String,
      label: json['label'] as String,
      values: values.map((key, value) {
        if (key is! String || value is! String) {
          throw const FormatException('Financial context values must be text');
        }
        return MapEntry(key, value);
      }),
      capabilities: capabilities.map((value) {
        if (value is! String) {
          throw const FormatException(
              'Financial context capabilities are invalid');
        }
        return value;
      }).toList(growable: false),
      provenance: json['provenance'] as String,
      effectiveFrom: _date(json['effectiveFrom']),
      effectiveUntil: _date(json['effectiveUntil']),
      active: json['active'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      status: json['status'] as String? ?? 'ACTIVE',
      conflictIds: ((json['conflictIds'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toRequestJson({bool includeProvenance = true}) => {
        'type': type,
        'label': label,
        'values': values,
        'capabilities': capabilities,
        if (includeProvenance) 'provenance': provenance,
        if (effectiveFrom != null) 'effectiveFrom': _dateString(effectiveFrom!),
        if (effectiveUntil != null)
          'effectiveUntil': _dateString(effectiveUntil!),
      };

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    final date = DateTime.parse((value as String).split('T').first);
    return DateTime.utc(date.year, date.month, date.day);
  }

  static String _dateString(DateTime value) =>
      value.toUtc().toIso8601String().substring(0, 10);
}

class FinancialContextList {
  const FinancialContextList({required this.asOf, required this.items});

  final DateTime asOf;
  final List<FinancialContextItem> items;

  factory FinancialContextList.fromJson(Map<String, dynamic> json) {
    if (json['asOf'] is! String || json['items'] is! List) {
      throw const FormatException('Invalid financial context response');
    }
    return FinancialContextList(
      asOf: DateTime.parse(json['asOf'] as String).toUtc(),
      items: (json['items'] as List)
          .map((item) => FinancialContextItem.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
    );
  }
}
