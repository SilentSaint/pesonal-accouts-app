package com.automaticexpense.tracker.domain;

import java.util.Objects;

public record PeriodSpending(DateRange period, Money total, int transactionCount) {
    public PeriodSpending {
        Objects.requireNonNull(period, "period cannot be null");
        Objects.requireNonNull(total, "total cannot be null");
        if (transactionCount < 0) {
            throw new IllegalArgumentException("transactionCount cannot be negative");
        }
    }
}
