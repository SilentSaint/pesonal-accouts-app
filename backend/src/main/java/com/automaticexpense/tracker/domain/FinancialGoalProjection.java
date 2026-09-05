package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.Objects;

public record FinancialGoalProjection(
    Money amountRemaining,
    int monthsRemaining,
    Money requiredMonthlyContribution,
    Money observedMonthlyContribution,
    LocalDate projectedCompletionDate,
    Money monthlyShortfallOrSurplus,
    boolean minimumBalanceBreached,
    GoalProjectionStatus status,
    List<String> contributionEvidenceReferences
) {
    public FinancialGoalProjection {
        Objects.requireNonNull(amountRemaining, "amountRemaining cannot be null");
        if (monthsRemaining < 0) {
            throw new IllegalArgumentException("monthsRemaining cannot be negative");
        }
        Objects.requireNonNull(requiredMonthlyContribution, "requiredMonthlyContribution cannot be null");
        Objects.requireNonNull(observedMonthlyContribution, "observedMonthlyContribution cannot be null");
        Objects.requireNonNull(monthlyShortfallOrSurplus, "monthlyShortfallOrSurplus cannot be null");
        Objects.requireNonNull(status, "status cannot be null");
        contributionEvidenceReferences = List.copyOf(Objects.requireNonNull(
            contributionEvidenceReferences, "contributionEvidenceReferences cannot be null"
        ));
    }
}
