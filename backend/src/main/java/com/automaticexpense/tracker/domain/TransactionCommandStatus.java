package com.automaticexpense.tracker.domain;

public enum TransactionCommandStatus {
    PENDING,
    PROCESSING,
    COMPLETED,
    NEEDS_REVIEW,
    FAILED;

    public boolean isTerminal() {
        return this == COMPLETED || this == NEEDS_REVIEW || this == FAILED;
    }
}
