package com.automaticexpense.tracker.domain;

import java.time.Instant;
import java.time.ZoneId;
import java.util.Objects;

public record FinanceQuery(String question, Instant asOf, ZoneId timezone, String currency) {
    public FinanceQuery {
        if (question == null || question.isBlank()) {
            throw new IllegalArgumentException("question cannot be blank");
        }
        if (question.length() > 500) {
            throw new IllegalArgumentException("question must be at most 500 characters");
        }
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(timezone, "timezone cannot be null");
        if (currency == null || !currency.matches("[A-Z]{3}")) {
            throw new IllegalArgumentException("currency must be a three-letter uppercase ISO code");
        }
    }
}
