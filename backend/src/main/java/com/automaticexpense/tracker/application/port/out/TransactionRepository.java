package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface TransactionRepository {
    void save(Transaction transaction);
    Optional<Transaction> findById(TransactionId id);
    List<Transaction> findByAccountId(AccountId accountId);
    List<Transaction> findByReconciliationStatus(ReconciliationStatus status);
    List<Transaction> findByAccountIdAndWindow(AccountId accountId, LocalDateTime startTime, LocalDateTime endTime);
    List<Transaction> findAllTransactions();
    void delete(TransactionId id);
}
