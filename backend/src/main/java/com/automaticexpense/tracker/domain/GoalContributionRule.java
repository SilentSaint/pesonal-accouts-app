package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.util.Objects;

public record GoalContributionRule(Money amount, GoalContributionCadence cadence) {
    public GoalContributionRule {
        if ((amount == null) != (cadence == null)) {
            throw new IllegalArgumentException("amount and cadence must either both be present or both be absent");
        }
        if (amount != null && amount.amount().signum() <= 0) {
            throw new IllegalArgumentException("contribution rule amount must be positive");
        }
    }

    public static GoalContributionRule none() {
        return new GoalContributionRule(null, null);
    }

    public boolean isConfigured() {
        return amount != null;
    }

    public Money monthlyAmount() {
        if (!isConfigured()) {
            return null;
        }
        BigDecimal monthly = switch (cadence) {
            case WEEKLY -> amount.amount().multiply(BigDecimal.valueOf(52)).divide(BigDecimal.valueOf(12), 2,
                java.math.RoundingMode.HALF_UP);
            case BIWEEKLY -> amount.amount().multiply(BigDecimal.valueOf(26)).divide(BigDecimal.valueOf(12), 2,
                java.math.RoundingMode.HALF_UP);
            case MONTHLY -> amount.amount();
            case QUARTERLY -> amount.amount().divide(BigDecimal.valueOf(3), 2, java.math.RoundingMode.HALF_UP);
            case YEARLY -> amount.amount().divide(BigDecimal.valueOf(12), 2, java.math.RoundingMode.HALF_UP);
        };
        return Money.of(monthly, amount.currency());
    }
}
