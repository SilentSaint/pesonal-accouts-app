package com.automaticexpense.tracker.application.port.in;

import java.time.Instant;
import java.time.ZoneId;
import java.util.Objects;

public record RefreshFinancialProjectionsRequest(
    String userId,
    Instant asOf,
    ZoneId timezone,
    String currency
) {
    public RefreshFinancialProjectionsRequest {
        if (userId == null || userId.isBlank()) throw new IllegalArgumentException("userId cannot be blank");
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(timezone, "timezone cannot be null");
        if (currency == null || !currency.matches("[A-Z]{3}")) {
            throw new IllegalArgumentException("currency must be a three-letter uppercase ISO code");
        }
    }
}
