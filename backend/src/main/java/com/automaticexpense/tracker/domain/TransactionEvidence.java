package com.automaticexpense.tracker.domain;

import java.time.LocalDateTime;
import java.util.Objects;

public record TransactionEvidence(
    String transactionId,
    LocalDateTime timestamp,
    String merchantName,
    Money personalSpend
) {
    public TransactionEvidence {
        Objects.requireNonNull(transactionId, "transactionId cannot be null");
        Objects.requireNonNull(timestamp, "timestamp cannot be null");
        Objects.requireNonNull(merchantName, "merchantName cannot be null");
        Objects.requireNonNull(personalSpend, "personalSpend cannot be null");
    }
}
