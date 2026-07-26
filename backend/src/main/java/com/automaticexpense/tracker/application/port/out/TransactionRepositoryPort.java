package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.ParsedTransactionEvent;

public interface TransactionRepositoryPort {
    void saveTransaction(ParsedTransactionEvent event);
}
