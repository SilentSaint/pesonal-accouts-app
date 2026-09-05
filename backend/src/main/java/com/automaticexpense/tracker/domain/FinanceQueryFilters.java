package com.automaticexpense.tracker.domain;

import java.util.Objects;
import java.util.Set;

public record FinanceQueryFilters(
    DateRange period,
    String currency,
    Set<AccountId> accountIds,
    String categoryId,
    String merchantName
) {
    public FinanceQueryFilters {
        Objects.requireNonNull(period, "period cannot be null");
        if (currency == null || !currency.matches("[A-Z]{3}")) {
            throw new IllegalArgumentException("currency must be a three-letter uppercase ISO code");
        }
        accountIds = Set.copyOf(accountIds == null ? Set.of() : accountIds);
    }

    public SpendingAnalyticsRequest asAnalyticsRequest() {
        return new SpendingAnalyticsRequest(period, currency, accountIds, categoryId, merchantName, 3);
    }
}
