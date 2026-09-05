package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.Objects;

/**
 * An observed allocation change. Negative values explicitly represent a withdrawal from this goal.
 */
public record GoalContribution(String id, Money amount, LocalDate contributedOn, String evidenceReference) {
    public GoalContribution {
        if (id == null || id.isBlank()) {
            throw new IllegalArgumentException("contribution id cannot be blank");
        }
        Objects.requireNonNull(amount, "contribution amount cannot be null");
        if (amount.amount().signum() == 0) {
            throw new IllegalArgumentException("contribution amount cannot be zero");
        }
        Objects.requireNonNull(contributedOn, "contributedOn cannot be null");
        if (evidenceReference != null && evidenceReference.isBlank()) {
            throw new IllegalArgumentException("evidenceReference cannot be blank");
        }
    }
}
