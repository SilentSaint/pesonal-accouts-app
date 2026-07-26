package com.automaticexpense.tracker.domain;

import java.util.Objects;

public record TransactionId(String value) {
    public TransactionId {
        Objects.requireNonNull(value, "TransactionId value cannot be null");
        if (value.isBlank()) {
            throw new IllegalArgumentException("TransactionId value cannot be blank");
        }
    }
}
