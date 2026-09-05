package com.automaticexpense.tracker.domain;

import java.util.Objects;
import java.util.Set;

public record DrillDownReference(
    DateRange period,
    String currency,
    Set<AccountId> accountIds,
    String categoryId,
    String merchantName
) {
    public DrillDownReference {
        Objects.requireNonNull(period, "period cannot be null");
        Objects.requireNonNull(currency, "currency cannot be null");
        accountIds = Set.copyOf(accountIds == null ? Set.of() : accountIds);
    }
}
