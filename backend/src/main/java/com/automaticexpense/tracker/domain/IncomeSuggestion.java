package com.automaticexpense.tracker.domain;

import java.util.Objects;

public record IncomeSuggestion(IncomeSource source, double confidence) {
    public IncomeSuggestion {
        Objects.requireNonNull(source, "source cannot be null");
        if (!Double.isFinite(confidence) || confidence < 0.0 || confidence > 1.0) {
            throw new IllegalArgumentException("confidence must be between zero and one");
        }
        if (source.confirmationStatus() != IncomeConfirmationStatus.PENDING) {
            throw new IllegalArgumentException("only pending income sources can be suggestions");
        }
    }
}
