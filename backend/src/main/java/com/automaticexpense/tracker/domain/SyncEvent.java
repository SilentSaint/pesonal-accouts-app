package com.automaticexpense.tracker.domain;

import java.time.LocalDateTime;
import java.util.Objects;

public record SyncEvent(
    String eventType, // TRANSACTION_INGESTED, ACCOUNT_UPDATED, DEBT_UPDATED, BILL_RECONCILED
    String entityId,
    String payload,
    LocalDateTime timestamp
) {
    public SyncEvent {
        Objects.requireNonNull(eventType, "eventType cannot be null");
        Objects.requireNonNull(entityId, "entityId cannot be null");
        timestamp = timestamp != null ? timestamp : LocalDateTime.now();
    }
}
