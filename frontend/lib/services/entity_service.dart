import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/merchant_entity.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'financial_data_cache.dart';

class EntityService extends ChangeNotifier {
  static final EntityService _instance = EntityService._internal();
  factory EntityService() => _instance;
  factory EntityService.forTesting({required AuthService authService}) =>
      EntityService._withAuth(authService);

  EntityService._internal() : _authService = AuthService() {
    _initialize();
  }

  EntityService._withAuth(this._authService) {
    _initialize();
  }

  final AuthService _authService;

  void _initialize() {
    _init();
    _authService.addListener(_onAuthenticationChanged);
  }

  final List<MerchantEntity> _entities = [];
  bool _isLoaded = false;
  String? _loadedUserId;

  List<MerchantEntity> get entities => List.unmodifiable(_entities);
  Future<void> ensureLoaded() async {
    final userId = _authService.currentUser?.id;
    if (userId == null) return;
    if (!_isLoaded || _loadedUserId != userId) {
      await _loadFromLocal(userId);
    }
  }

  Future<void> _init() async {
    await _authService.ensureInitialized();
    final userId = _authService.currentUser?.id;
    if (userId != null) {
      await _loadFromLocal(userId);
      _fetchFromBackend(userId);
    }
  }

  void _onAuthenticationChanged() {
    if (_authService.currentUser?.id != _loadedUserId) {
      _entities.clear();
      _isLoaded = false;
      _loadedUserId = null;
      notifyListeners();
    }
  }

  bool _isCurrentUser(String userId) => _authService.currentUser?.id == userId;

  Future<void> _loadFromLocal(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_isCurrentUser(userId)) return;
      final raw = prefs.getString(FinancialDataCache.merchantEntitiesKey);
      _entities.clear();
      if (raw != null) {
        final List<dynamic> list = jsonDecode(raw);
        _entities.addAll(list.map((e) =>
            MerchantEntity.fromJson(Map<String, dynamic>.from(e as Map))));
        _entities.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      }
    } catch (e) {
      debugPrint('EntityService: error loading local entities: $e');
    }
    if (_isCurrentUser(userId)) {
      _isLoaded = true;
      _loadedUserId = userId;
      notifyListeners();
    }
  }

  Future<void> _saveToLocal(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_isCurrentUser(userId)) return;
      final raw = jsonEncode(_entities.map((e) => e.toJson()).toList());
      await prefs.setString(FinancialDataCache.merchantEntitiesKey, raw);
    } catch (e) {
      debugPrint('EntityService: error saving local entities: $e');
    }
  }

  Future<void> _fetchFromBackend(String userId) async {
    final auth = _authService;
    if (!_isCurrentUser(userId)) return;

    try {
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/entities'),
            headers: auth.withBackendAuthorization({
              'Content-Type': 'application/json',
              if (auth.idToken != null)
                'Authorization': 'Bearer ${auth.idToken}',
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200 && _isCurrentUser(userId)) {
        final List<dynamic> list = jsonDecode(resp.body);
        if (list.isNotEmpty) {
          final serverEntities = list
              .map((e) =>
                  MerchantEntity.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          _entities.clear();
          for (final serverEnt in serverEntities) {
            final idx = _entities.indexWhere((e) =>
                e.id == serverEnt.id ||
                e.name.toLowerCase() == serverEnt.name.toLowerCase());
            if (idx >= 0) {
              // Merge aliases
              final mergedUpi = {
                ..._entities[idx].upiAliases,
                ...serverEnt.upiAliases
              }.toList();
              final mergedAcct = {
                ..._entities[idx].accountAliases,
                ...serverEnt.accountAliases
              }.toList();
              _entities[idx] = _entities[idx].copyWith(
                upiAliases: mergedUpi,
                accountAliases: mergedAcct,
                defaultCategory:
                    serverEnt.defaultCategory ?? _entities[idx].defaultCategory,
                lastUsedAt:
                    serverEnt.lastUsedAt.isAfter(_entities[idx].lastUsedAt)
                        ? serverEnt.lastUsedAt
                        : _entities[idx].lastUsedAt,
              );
            } else {
              _entities.add(serverEnt);
            }
          }
          _entities.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
          await _saveToLocal(userId);
          if (_isCurrentUser(userId)) {
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('EntityService: backend sync error: $e');
    }
  }

  static bool isPlatformAggregator(String? name) {
    if (name == null || name.isEmpty) return false;
    final lower = name.toLowerCase();
    return lower.contains('dreamplug') ||
        lower.contains('dream plug') ||
        lower.contains('razorpay') ||
        lower.contains('payu') ||
        lower.contains('billdesk') ||
        lower.contains('cashfree') ||
        lower.contains('ccavenue') ||
        lower.contains('one97') ||
        lower.contains('bharat billpay') ||
        lower.contains('bbps');
  }

  /// Matches an existing entity by UPI ID, Vendor Alias, Account Mask, or Payee Name
  MerchantEntity? matchEntity(
      {String? upiId, String? accountMask, String? rawName}) {
    if (upiId != null && upiId.trim().isNotEmpty) {
      final cleanUpi = upiId.toLowerCase().trim();
      for (final e in _entities) {
        if (e.upiAliases.any((u) => u.toLowerCase().trim() == cleanUpi)) {
          return e;
        }
      }
    }

    if (rawName != null && rawName.trim().isNotEmpty) {
      final cleanName = rawName.toLowerCase().trim();
      final isAggregator = isPlatformAggregator(cleanName);

      // If it's a multi-service platform aggregator and not matched by UPI ID,
      // DO NOT do loose vendor alias matching!
      if (!isAggregator) {
        // Match against vendor aliases (e.g. "Saira Banu" was aliased to "My Maid")
        for (final e in _entities) {
          if (e.vendorAliases.any((v) => v.toLowerCase().trim() == cleanName)) {
            return e;
          }
        }
        // Direct canonical name match
        for (final e in _entities) {
          if (e.name.toLowerCase().trim() == cleanName) {
            return e;
          }
        }
        // Substring match on vendor aliases
        for (final e in _entities) {
          if (e.vendorAliases.any((v) =>
              cleanName.contains(v.toLowerCase().trim()) ||
              v.toLowerCase().trim().contains(cleanName))) {
            return e;
          }
        }
        // Substring match on canonical name
        for (final e in _entities) {
          if (cleanName.contains(e.name.toLowerCase().trim()) ||
              e.name.toLowerCase().trim().contains(cleanName)) {
            return e;
          }
        }
      }
    }

    return null;
  }

  /// Maps a transaction to an Entity (creates or updates alias history)
  Future<MerchantEntity> mapTransactionToEntity({
    required String entityName,
    String? rawVendorName,
    String? upiId,
    String? accountMask,
    String? category,
    String? subCategory,
    bool mapByUpiOnly = false,
  }) async {
    final userId = _authService.currentUser?.id;
    if (userId == null) {
      throw StateError('An authenticated user is required to map an entity.');
    }
    final cleanName = entityName.trim();
    final cleanVendor = rawVendorName?.trim();
    final cleanUpi = upiId?.toLowerCase().trim();
    final cleanAcct = accountMask?.trim();
    final cleanSub = subCategory?.trim();
    final shouldSkipVendorAlias = mapByUpiOnly ||
        (cleanUpi != null &&
            cleanUpi.isNotEmpty &&
            isPlatformAggregator(cleanVendor));

    final existingIndex = _entities.indexWhere(
        (e) => e.name.toLowerCase().trim() == cleanName.toLowerCase());

    MerchantEntity target;
    if (existingIndex >= 0) {
      final existing = _entities[existingIndex];
      final newUpiList = List<String>.from(existing.upiAliases);
      if (cleanUpi != null &&
          cleanUpi.isNotEmpty &&
          !newUpiList.contains(cleanUpi)) {
        newUpiList.add(cleanUpi);
      }

      final newVendorList = List<String>.from(existing.vendorAliases);
      // Strip corrupted broad aggregator names
      newVendorList.removeWhere((v) => isPlatformAggregator(v));
      if (!shouldSkipVendorAlias &&
          cleanVendor != null &&
          cleanVendor.isNotEmpty &&
          cleanVendor.toLowerCase() != cleanName.toLowerCase() &&
          !newVendorList.contains(cleanVendor)) {
        newVendorList.add(cleanVendor);
      }

      final newAcctList = List<String>.from(existing.accountAliases);
      if (cleanAcct != null &&
          cleanAcct.isNotEmpty &&
          !newAcctList.contains(cleanAcct)) {
        newAcctList.add(cleanAcct);
      }

      target = existing.copyWith(
        upiAliases: newUpiList,
        vendorAliases: newVendorList,
        accountAliases: newAcctList,
        defaultCategory: category ?? existing.defaultCategory,
        defaultSubCategory: (cleanSub != null && cleanSub.isNotEmpty)
            ? cleanSub
            : existing.defaultSubCategory,
        lastUsedAt: DateTime.now(),
      );
      _entities[existingIndex] = target;
    } else {
      final initialVendors = (!shouldSkipVendorAlias &&
              cleanVendor != null &&
              cleanVendor.isNotEmpty &&
              cleanVendor.toLowerCase() != cleanName.toLowerCase())
          ? [cleanVendor]
          : <String>[];

      target = MerchantEntity(
        id: 'entity-${DateTime.now().millisecondsSinceEpoch}',
        name: cleanName,
        defaultCategory: category ?? 'General Expenses',
        defaultSubCategory:
            (cleanSub != null && cleanSub.isNotEmpty) ? cleanSub : null,
        upiAliases: cleanUpi != null && cleanUpi.isNotEmpty ? [cleanUpi] : [],
        vendorAliases: initialVendors,
        accountAliases:
            cleanAcct != null && cleanAcct.isNotEmpty ? [cleanAcct] : [],
        createdAt: DateTime.now(),
        lastUsedAt: DateTime.now(),
      );
      _entities.insert(0, target);
    }

    _entities.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    await _saveToLocal(userId);
    if (_isCurrentUser(userId)) {
      notifyListeners();
    }

    // Sync to backend asynchronously
    _syncEntityToBackend(target, userId);

    return target;
  }

  Future<void> _syncEntityToBackend(
      MerchantEntity entity, String userId) async {
    final auth = _authService;
    if (!_isCurrentUser(userId)) return;

    try {
      await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/entities'),
            headers: auth.withBackendAuthorization({
              'Content-Type': 'application/json',
              if (auth.idToken != null)
                'Authorization': 'Bearer ${auth.idToken}',
            }),
            body: jsonEncode(entity.toJson()),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('EntityService: failed to sync entity to backend: $e');
    }
  }

  /// Automatically registers a discovered merchant if not yet existing as an entity
  Future<void> registerDiscoveredMerchant({
    required String name,
    String? category,
    String? subCategory,
    String? upiId,
    String? accountMask,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty ||
        cleanName == 'Self Transfer' ||
        cleanName == 'Bank Alert') return;
    await ensureLoaded();
    final userId = _authService.currentUser?.id;
    if (userId == null) return;

    final existing = _entities
        .where((e) => e.name.toLowerCase().trim() == cleanName.toLowerCase())
        .firstOrNull;
    if (existing == null) {
      final newEntity = MerchantEntity(
        id: 'entity-${DateTime.now().millisecondsSinceEpoch}-${_entities.length}',
        name: cleanName,
        defaultCategory: category ?? 'General Expenses',
        defaultSubCategory: (subCategory != null && subCategory.isNotEmpty)
            ? subCategory
            : null,
        upiAliases: (upiId != null && upiId.isNotEmpty)
            ? [upiId.toLowerCase().trim()]
            : [],
        accountAliases: (accountMask != null && accountMask.isNotEmpty)
            ? [accountMask]
            : [],
        createdAt: DateTime.now(),
        lastUsedAt: DateTime.now(),
      );
      _entities.add(newEntity);
      _entities.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      await _saveToLocal(userId);
      if (_isCurrentUser(userId)) {
        notifyListeners();
      }
    } else {
      bool changed = false;
      List<String> newUpis = List.from(existing.upiAliases);
      final cleanUpi = upiId?.toLowerCase().trim();
      if (cleanUpi != null &&
          cleanUpi.isNotEmpty &&
          !newUpis.contains(cleanUpi)) {
        newUpis.add(cleanUpi);
        changed = true;
      }
      if (changed || (existing.defaultCategory == null && category != null)) {
        final idx = _entities.indexOf(existing);
        _entities[idx] = existing.copyWith(
          upiAliases: newUpis,
          defaultCategory: existing.defaultCategory ?? category,
          defaultSubCategory: existing.defaultSubCategory ?? subCategory,
          lastUsedAt: DateTime.now(),
        );
        await _saveToLocal(userId);
        if (_isCurrentUser(userId)) {
          notifyListeners();
        }
      }
    }
  }
}
