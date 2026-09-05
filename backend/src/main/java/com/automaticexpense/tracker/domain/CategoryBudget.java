package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Objects;

public class CategoryBudget {
    private final String id;
    private final String categoryId;
    private final String categoryName;
    private final String yearMonth;
    private final Money limitAmount;
    private Money currentSpend;

    public CategoryBudget(String categoryId, Money limitAmount, Money currentSpend) {
        this(categoryId, categoryId, categoryId, "DEFAULT", limitAmount, currentSpend);
    }

    public CategoryBudget(
        String id,
        String categoryId,
        String categoryName,
        String yearMonth,
        Money limitAmount,
        Money currentSpend
    ) {
        this.id = id != null ? id : categoryId;
        this.categoryId = Objects.requireNonNull(categoryId, "categoryId cannot be null");
        this.categoryName = categoryName != null ? categoryName : categoryId;
        this.yearMonth = yearMonth != null ? yearMonth : "DEFAULT";
        this.limitAmount = Objects.requireNonNull(limitAmount, "limitAmount cannot be null");
        this.currentSpend = currentSpend != null ? currentSpend : Money.zero(limitAmount.currency());
    }

    public void addSpend(Money amount) {
        if (amount != null && amount.currency().equalsIgnoreCase(limitAmount.currency())) {
            this.currentSpend = this.currentSpend.add(amount);
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

    public Money remainingBudget() {
        if (currentSpend.isGreaterThanOrEqualTo(limitAmount)) {
            return Money.zero(limitAmount.currency());
        }
        return limitAmount.subtract(currentSpend);
    }

    public String id() {
        return id;
    }

    public String categoryId() {
        return categoryId;
    }

    public String categoryName() {
        return categoryName;
    }

    public String yearMonth() {
        return yearMonth;
    }

    public Money limitAmount() {
        return limitAmount;
    }

    public Money currentSpend() {
        return currentSpend;
    }
}
