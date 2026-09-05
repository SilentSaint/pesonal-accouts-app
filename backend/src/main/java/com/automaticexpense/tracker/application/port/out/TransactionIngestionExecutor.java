package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.application.TransactionCommand;
import com.automaticexpense.tracker.domain.Transaction;

public interface TransactionIngestionExecutor {
    Transaction ingest(TransactionCommand command);
}
