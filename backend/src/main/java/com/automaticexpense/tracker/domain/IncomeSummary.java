package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.Objects;

/**
 * Income amounts separated by certainty: observed transaction evidence, scheduled confirmed
 * sources, and still-unconfirmed suggestions.
 */
public record IncomeSummary(
    LocalDate periodStart,
    LocalDate periodEnd,
    LocalDate asOf,
    Money observed,
    Money expected,
    Money uncertain,
    int confirmedSourceCount,
    int unconfirmedSuggestionCount
) {
    public IncomeSummary {
        Objects.requireNonNull(periodStart, "periodStart cannot be null");
        Objects.requireNonNull(periodEnd, "periodEnd cannot be null");
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(observed, "observed cannot be null");
        Objects.requireNonNull(expected, "expected cannot be null");
        Objects.requireNonNull(uncertain, "uncertain cannot be null");
        if (periodEnd.isBefore(periodStart)) {
            throw new IllegalArgumentException("periodEnd cannot be before periodStart");
        }
        if (!observed.currency().equalsIgnoreCase(expected.currency())
            || !observed.currency().equalsIgnoreCase(uncertain.currency())) {
            throw new IllegalArgumentException("income summary amounts must have the same currency");
        }
        if (confirmedSourceCount < 0 || unconfirmedSuggestionCount < 0) {
            throw new IllegalArgumentException("source counts cannot be negative");
        }
    }
}
