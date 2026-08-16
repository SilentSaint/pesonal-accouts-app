package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Objects;

public class CategoryBudget {
    private final String categoryId;
    private final Money limitAmount;
    private Money currentSpend;

    public CategoryBudget(String categoryId, Money limitAmount, Money currentSpend) {
        this.categoryId = Objects.requireNonNull(categoryId, "categoryId cannot be null");
        this.limitAmount = Objects.requireNonNull(limitAmount, "limitAmount cannot be null");
        this.currentSpend = currentSpend != null ? currentSpend : new Money(BigDecimal.ZERO, limitAmount.currency());
    }

    public void addSpend(Money amount) {
        if (amount != null && amount.currency().equals(limitAmount.currency())) {
            this.currentSpend = new Money(this.currentSpend.amount().add(amount.amount()), limitAmount.currency());
        }
    }

    public double getSpendPercentage() {
        if (limitAmount.amount().compareTo(BigDecimal.ZERO) == 0) return 0.0;
        return currentSpend.amount()
            .multiply(new BigDecimal("100"))
            .divide(limitAmount.amount(), 2, RoundingMode.HALF_UP)
            .doubleValue();
    }

    public boolean isThreshold80Reached() {
        return getSpendPercentage() >= 80.0;
    }

    public boolean isThreshold100Reached() {
        return getSpendPercentage() >= 100.0;
    }

    public String categoryId() {
        return categoryId;
    }

    public Money limitAmount() {
        return limitAmount;
    }

    public Money currentSpend() {
        return currentSpend;
    }
}
