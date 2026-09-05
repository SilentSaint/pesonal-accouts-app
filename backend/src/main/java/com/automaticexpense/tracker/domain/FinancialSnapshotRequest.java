package com.automaticexpense.tracker.domain;

import java.time.Instant;
import java.time.ZoneId;
import java.util.Objects;
import java.util.Set;

public record FinancialSnapshotRequest(
    Instant asOf,
    ZoneId timezone,
    Set<AccountId> accountIds,
    String currency
) {
    public FinancialSnapshotRequest {
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(timezone, "timezone cannot be null");
        accountIds = Set.copyOf(accountIds == null ? Set.of() : accountIds);
        if (currency == null || !currency.matches("[A-Z]{3}")) {
            throw new IllegalArgumentException("currency must be a three-letter uppercase ISO code");
        }
    }
}
