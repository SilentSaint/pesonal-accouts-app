package com.automaticexpense.tracker.domain;

import java.util.Objects;

public record TransactionCommandReference(String userScopeId, TransactionId commandId) {
    public TransactionCommandReference {
        if (userScopeId == null || userScopeId.isBlank()) {
            throw new IllegalArgumentException("userScopeId cannot be blank");
        }
        Objects.requireNonNull(commandId, "commandId cannot be null");
    }
}
