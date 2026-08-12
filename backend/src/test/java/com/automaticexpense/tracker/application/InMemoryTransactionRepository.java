package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

public class InMemoryTransactionRepository implements TransactionRepository {
    private final Map<TransactionId, Transaction> transactions = new ConcurrentHashMap<>();

    @Override
    public void save(Transaction transaction) {
        transactions.put(transaction.id(), transaction);
    }

    @Override
    public Optional<Transaction> findById(TransactionId id) {
        return Optional.ofNullable(transactions.get(id));
    }

    @Override
    public List<Transaction> findByAccountId(AccountId accountId) {
        return transactions.values().stream()
            .filter(txn -> txn.accountId().equals(accountId))
            .collect(Collectors.toList());
    }

    @Override
    public List<Transaction> findByReconciliationStatus(ReconciliationStatus status) {
        return transactions.values().stream()
            .filter(txn -> txn.reconciliationStatus() == status || (status == ReconciliationStatus.NEEDS_REVIEW && txn.categoryId() == null))
            .collect(Collectors.toList());
    }

    @Override
    public List<Transaction> findByAccountIdAndWindow(AccountId accountId, LocalDateTime startTime, LocalDateTime endTime) {
        return transactions.values().stream()
            .filter(txn -> txn.accountId().equals(accountId))
            .filter(txn -> !txn.timestamp().isBefore(startTime) && !txn.timestamp().isAfter(endTime))
            .collect(Collectors.toList());
    }

    @Override
    public void delete(TransactionId id) {
        transactions.remove(id);
    }
}
