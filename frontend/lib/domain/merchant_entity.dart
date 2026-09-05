class MerchantEntity {
  final String id;
  final String name; // Canonical entity / custom user alias (e.g. "My Maid", "Chai Point", "Swiggy")
  final String? defaultCategory; // e.g. "Food & Dining", "Personal Transfers"
  final String? defaultSubCategory; // e.g. "Tea & Snacks"
  final List<String> upiAliases; // e.g. ["paytm.s1yxlpq@pty", "sairabanu@oksbi"]
  final List<String> vendorAliases; // e.g. ["Saira Banu", "SAIRA BANU"]
  final List<String> accountAliases; // e.g. ["•••• 1277"]
  final DateTime createdAt;
  final DateTime lastUsedAt;

  MerchantEntity({
    required this.id,
    required this.name,
    this.defaultCategory,
    this.defaultSubCategory,
    this.upiAliases = const [],
    this.vendorAliases = const [],
    this.accountAliases = const [],
    required this.createdAt,
    required this.lastUsedAt,
  });

  MerchantEntity copyWith({
    String? name,
    String? defaultCategory,
    String? defaultSubCategory,
    List<String>? upiAliases,
    List<String>? vendorAliases,
    List<String>? accountAliases,
    DateTime? lastUsedAt,
  }) {
    return MerchantEntity(
      id: id,
      name: name ?? this.name,
      defaultCategory: defaultCategory ?? this.defaultCategory,
      defaultSubCategory: defaultSubCategory ?? this.defaultSubCategory,
      upiAliases: upiAliases ?? this.upiAliases,
      vendorAliases: vendorAliases ?? this.vendorAliases,
      accountAliases: accountAliases ?? this.accountAliases,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'defaultCategory': defaultCategory,
    'defaultSubCategory': defaultSubCategory,
    'upiAliases': upiAliases,
    'vendorAliases': vendorAliases,
    'accountAliases': accountAliases,
    'createdAt': createdAt.toIso8601String(),
    'lastUsedAt': lastUsedAt.toIso8601String(),
  };

  factory MerchantEntity.fromJson(Map<String, dynamic> json) => MerchantEntity(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    defaultCategory: json['defaultCategory'] as String?,
    defaultSubCategory: json['defaultSubCategory'] as String?,
    upiAliases: (json['upiAliases'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    vendorAliases: (json['vendorAliases'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    accountAliases: (json['accountAliases'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    lastUsedAt: DateTime.tryParse(json['lastUsedAt'] ?? '') ?? DateTime.now(),
  );
}
