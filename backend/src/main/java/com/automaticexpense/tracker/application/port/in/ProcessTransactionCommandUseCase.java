package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.TransactionCommandReference;

public interface ProcessTransactionCommandUseCase {
    void process(TransactionCommandReference reference);
}
