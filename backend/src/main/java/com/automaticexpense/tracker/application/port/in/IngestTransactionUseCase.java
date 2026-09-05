package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.BackfillResult;
import com.automaticexpense.tracker.domain.EmailAccountConfig;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;

import java.time.LocalDateTime;
import java.util.List;

public interface IngestTransactionUseCase {
    Transaction ingestManualTransaction(IngestTransactionCommand command);
    default Transaction ingestManualTransaction(
        IngestTransactionCommand command,
        TransactionId commandId
    ) {
        return ingestManualTransaction(command);
    }
    Transaction ingestSmsTransaction(String sender, String body, LocalDateTime receivedAt);
    Transaction ingestEmailTransaction(String sender, String subject, String body, LocalDateTime receivedAt);
    List<Transaction> getPendingReviewTransactions();
    Transaction confirmTransaction(TransactionId id, String categoryId);
    Transaction mergeTransactions(TransactionId targetId, TransactionId duplicateId);
    Transaction assignCategoryAndLearnRule(
        TransactionId id,
        String categoryId,
        String subCategory,
        String payeeNickname
    );
    default Transaction assignCategoryAndLearnRule(
        TransactionId id,
        String categoryId,
        String payeeNickname
    ) {
        return assignCategoryAndLearnRule(id, categoryId, null, payeeNickname);
    }
    BackfillResult execute30DayBackfill(List<String> smsBodies, List<String> emailBodies);
    EmailAccountConfig linkEmailAccount(String emailAddress);
    List<EmailAccountConfig> getLinkedEmailAccounts();
}
