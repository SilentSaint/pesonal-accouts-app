package com.automaticexpense.tracker.domain;

import java.util.List;

public record FinancialEvidencePage(List<Transaction> transactions, String nextCursor) {
    public FinancialEvidencePage {
        transactions = List.copyOf(transactions == null ? List.of() : transactions);
    }
}
