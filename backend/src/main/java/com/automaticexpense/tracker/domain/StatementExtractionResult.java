package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.Objects;

public record StatementExtractionResult(
    String cardIdentifier,
    String cardName,
    LocalDate statementDate,
    Money totalDue,
    Money minimumDue,
    LocalDate paymentDueDate,
    List<StatementTransaction> transactions
) {
    public StatementExtractionResult {
        Objects.requireNonNull(cardIdentifier, "cardIdentifier cannot be null");
        Objects.requireNonNull(cardName, "cardName cannot be null");
        Objects.requireNonNull(totalDue, "totalDue cannot be null");
        Objects.requireNonNull(paymentDueDate, "paymentDueDate cannot be null");
        transactions = transactions != null ? List.copyOf(transactions) : List.of();
    }
}
