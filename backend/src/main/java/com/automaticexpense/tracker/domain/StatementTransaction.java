package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.Objects;

public record StatementTransaction(
    LocalDate date,
    String merchantName,
    Money amount,
    TransactionType type,
    String referenceNumber
) {
    public StatementTransaction {
        Objects.requireNonNull(date, "date cannot be null");
        Objects.requireNonNull(merchantName, "merchantName cannot be null");
        Objects.requireNonNull(amount, "amount cannot be null");
        Objects.requireNonNull(type, "type cannot be null");
    }
}
