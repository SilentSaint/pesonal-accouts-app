import 'package:automatic_expense_tracker/services/financial_data_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('clears every locally cached financial record on sign-out', () async {
    SharedPreferences.setMockInitialValues({
      FinancialDataCache.accountsKey: '[{"id":"account-test"}]',
      FinancialDataCache.recentTransactionsKey: '[{"id":"transaction-test"}]',
      FinancialDataCache.pendingTransactionsKey: '[{"id":"pending-test"}]',
      FinancialDataCache.categoryTotalsKey: '{"Food":100}',
      FinancialDataCache.backfillCompleteKey: true,
      FinancialDataCache.backfillTimeKey: 123,
      FinancialDataCache.merchantEntitiesKey: '[{"name":"Merchant"}]',
      FinancialDataCache.customSubcategoriesKey: '{"Food":["Cafe"]}',
      FinancialDataCache.promotionalBlacklistKey: ['Promotion'],
    });
    final preferences = await SharedPreferences.getInstance();

    await FinancialDataCache(preferences).clear();

    expect(preferences.containsKey(FinancialDataCache.accountsKey), isFalse);
    expect(
      preferences.containsKey(FinancialDataCache.recentTransactionsKey),
      isFalse,
    );
    expect(
      preferences.containsKey(FinancialDataCache.pendingTransactionsKey),
      isFalse,
    );
    expect(
      preferences.containsKey(FinancialDataCache.categoryTotalsKey),
      isFalse,
    );
    expect(
      preferences.containsKey(FinancialDataCache.backfillCompleteKey),
      isFalse,
    );
    expect(
      preferences.containsKey(FinancialDataCache.backfillTimeKey),
      isFalse,
    );
    expect(
      preferences.containsKey(FinancialDataCache.merchantEntitiesKey),
      isFalse,
    );
    expect(
      preferences.containsKey(FinancialDataCache.customSubcategoriesKey),
      isFalse,
    );
    expect(
      preferences.containsKey(FinancialDataCache.promotionalBlacklistKey),
      isFalse,
    );
  });
}
