package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;

import java.time.LocalDateTime;
import java.util.List;

public interface IngestTransactionUseCase {
    Transaction ingestManualTransaction(IngestTransactionCommand command);
    Transaction ingestSmsTransaction(String sender, String body, LocalDateTime receivedAt);
    Transaction ingestEmailTransaction(String sender, String subject, String body, LocalDateTime receivedAt);
    List<Transaction> getPendingReviewTransactions();
    Transaction confirmTransaction(TransactionId id, String categoryId);
    Transaction mergeTransactions(TransactionId targetId, TransactionId duplicateId);
}
