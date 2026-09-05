package com.automaticexpense.tracker.domain;

public record FinanceQueryClarification(String message) implements FinanceQueryPlanningResult {
    public FinanceQueryClarification {
        if (message == null || message.isBlank()) {
            throw new IllegalArgumentException("message cannot be blank");
        }
    }
}
