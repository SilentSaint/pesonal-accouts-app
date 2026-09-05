package com.automaticexpense.tracker.domain;

import java.time.Instant;
import java.time.ZoneId;
import java.util.Objects;

public record FinancialEvidenceQuery(
    SpendingAnalyticsRequest filters,
    Instant asOf,
    ZoneId timezone,
    int pageSize,
    String cursor
) {
    public FinancialEvidenceQuery {
        Objects.requireNonNull(filters, "filters cannot be null");
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(timezone, "timezone cannot be null");
        if (pageSize < 1 || pageSize > 100) {
            throw new IllegalArgumentException("pageSize must be between one and 100");
        }
    }
}
