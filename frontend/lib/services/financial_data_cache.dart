import 'package:shared_preferences/shared_preferences.dart';

class FinancialDataCache {
  static const accountsKey = 'saved_accounts';
  static const recentTransactionsKey = 'saved_recent_txns';
  static const pendingTransactionsKey = 'saved_pending_txns';
  static const categoryTotalsKey = 'saved_category_totals';
  static const backfillCompleteKey = 'is_historical_backfilled';
  static const backfillTimeKey = 'last_backfill_scan_ms';
  static const merchantEntitiesKey = 'saved_merchant_entities';
  static const customSubcategoriesKey = 'saved_custom_subcategories';
  static const promotionalBlacklistKey = 'saved_promotional_blacklist';

  static const _keys = [
    accountsKey,
    recentTransactionsKey,
    pendingTransactionsKey,
    categoryTotalsKey,
    backfillCompleteKey,
    backfillTimeKey,
    merchantEntitiesKey,
    customSubcategoriesKey,
    promotionalBlacklistKey,
  ];

  FinancialDataCache(this._preferences);

  final SharedPreferences _preferences;

  Future<void> clear() async {
    for (final key in _keys) {
      await _preferences.remove(key);
    }
  }
}
