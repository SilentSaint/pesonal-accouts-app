package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.Objects;

/**
 * The minimum balance from the authoritative cash-flow forecast before the required goal contribution.
 */
public record GoalCashFlowImpact(Money forecastMinimumBalance, Money preferredMinimumBalance, LocalDate asOf) {
    public GoalCashFlowImpact {
        Objects.requireNonNull(forecastMinimumBalance, "forecastMinimumBalance cannot be null");
        Objects.requireNonNull(preferredMinimumBalance, "preferredMinimumBalance cannot be null");
        forecastMinimumBalance.compareTo(preferredMinimumBalance);
        Objects.requireNonNull(asOf, "asOf cannot be null");
    }
}
