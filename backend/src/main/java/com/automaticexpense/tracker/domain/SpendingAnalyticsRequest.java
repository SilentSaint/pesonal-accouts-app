package com.automaticexpense.tracker.domain;

import java.util.Objects;
import java.util.Set;

public record SpendingAnalyticsRequest(
    DateRange period,
    String currency,
    Set<AccountId> accountIds,
    String categoryId,
    String merchantName,
    int rollingPeriodCount
) {
    public SpendingAnalyticsRequest {
        Objects.requireNonNull(period, "period cannot be null");
        if (currency == null || !currency.matches("[A-Z]{3}")) {
            throw new IllegalArgumentException("currency must be a three-letter uppercase ISO code");
        }
        accountIds = Set.copyOf(accountIds == null ? Set.of() : accountIds);
        if (rollingPeriodCount < 1) {
            throw new IllegalArgumentException("rollingPeriodCount must be at least one");
        }
    }
}
