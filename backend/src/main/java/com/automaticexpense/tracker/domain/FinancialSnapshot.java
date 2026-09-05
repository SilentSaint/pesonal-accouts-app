package com.automaticexpense.tracker.domain;

import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import java.util.Objects;

public record FinancialSnapshot(Instant asOf, ZoneId timezone, List<Transaction> canonicalTransactions) {
    public FinancialSnapshot {
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(timezone, "timezone cannot be null");
        canonicalTransactions = List.copyOf(Objects.requireNonNull(
            canonicalTransactions, "canonicalTransactions cannot be null"
        ));
    }
}
