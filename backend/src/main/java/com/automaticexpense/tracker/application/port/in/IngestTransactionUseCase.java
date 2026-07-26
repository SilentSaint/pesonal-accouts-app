package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.Transaction;

import java.time.LocalDateTime;

public interface IngestTransactionUseCase {
    Transaction ingestManualTransaction(IngestTransactionCommand command);
    Transaction ingestSmsTransaction(String sender, String body, LocalDateTime receivedAt);
}
