package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Objects;

public record ExpectedAmountRange(Money minimum, Money maximum) {
    public ExpectedAmountRange {
        Objects.requireNonNull(minimum, "minimum cannot be null");
        Objects.requireNonNull(maximum, "maximum cannot be null");
        if (!minimum.currency().equalsIgnoreCase(maximum.currency())) {
            throw new IllegalArgumentException("Expected amount range must use one currency");
        }
        if (minimum.compareTo(maximum) > 0) {
            throw new IllegalArgumentException("Expected amount range minimum cannot exceed maximum");
        }
    }

    public boolean isVariable() {
        return minimum.compareTo(maximum) != 0;
    }

    public Money nominalAmount() {
        return Money.of(
            minimum.amount().add(maximum.amount()).divide(BigDecimal.valueOf(2), 2, RoundingMode.HALF_UP),
            minimum.currency()
        );
    }
}
