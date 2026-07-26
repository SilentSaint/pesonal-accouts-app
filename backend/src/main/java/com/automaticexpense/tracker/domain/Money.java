package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Objects;

public record Money(BigDecimal amount, String currency) {

    public Money {
        Objects.requireNonNull(amount, "Amount cannot be null");
        Objects.requireNonNull(currency, "Currency cannot be null");
        amount = amount.setScale(2, RoundingMode.HALF_UP);
    }

    public Money add(Money other) {
        validateSameCurrency(other);
        return new Money(this.amount.add(other.amount), this.currency);
    }

    public Money subtract(Money other) {
        validateSameCurrency(other);
        return new Money(this.amount.subtract(other.amount), this.currency);
    }

    private void validateSameCurrency(Money other) {
        if (!this.currency.equalsIgnoreCase(other.currency)) {
            throw new IllegalArgumentException("Cannot operate on different currencies: " + this.currency + " vs " + other.currency);
        }
    }
}
