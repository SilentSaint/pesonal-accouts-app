package com.automaticexpense.tracker.domain;

import java.util.Objects;

public record SpendingBreakdown(String key, Money total, int transactionCount) {
    public SpendingBreakdown {
        if (key == null || key.isBlank()) {
            throw new IllegalArgumentException("key cannot be blank");
        }
        Objects.requireNonNull(total, "total cannot be null");
        if (transactionCount < 0) {
            throw new IllegalArgumentException("transactionCount cannot be negative");
        }
    }
}
