package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.automaticexpense.tracker.domain.TransactionCommandStatus;
import com.automaticexpense.tracker.domain.TransactionId;

import java.util.Objects;

public record TransactionCommand(
    String userScopeId,
    TransactionId id,
    IngestTransactionCommand payload,
    TransactionCommandStatus status,
    String failureReason,
    boolean enqueued
) {
    public TransactionCommand {
        if (userScopeId == null || userScopeId.isBlank()) {
            throw new IllegalArgumentException("userScopeId cannot be blank");
        }
        Objects.requireNonNull(id, "id cannot be null");
        Objects.requireNonNull(payload, "payload cannot be null");
        Objects.requireNonNull(status, "status cannot be null");
    }

    public TransactionCommand withStatus(TransactionCommandStatus nextStatus, String nextFailureReason) {
        return new TransactionCommand(userScopeId, id, payload, nextStatus, nextFailureReason, enqueued);
    }

    public TransactionCommand asEnqueued() {
        return new TransactionCommand(userScopeId, id, payload, status, failureReason, true);
    }

    public TransactionCommandReference reference() {
        return new TransactionCommandReference(userScopeId, id);
    }
}
