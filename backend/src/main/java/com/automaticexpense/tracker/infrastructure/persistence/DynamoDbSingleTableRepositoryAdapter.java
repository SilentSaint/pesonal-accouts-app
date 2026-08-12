package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.AccountRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.*;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

public class DynamoDbSingleTableRepositoryAdapter implements AccountRepository, TransactionRepository {

    private final String userId;
    private final Map<String, Map<String, String>> tableStorage = new ConcurrentHashMap<>();

    public DynamoDbSingleTableRepositoryAdapter(String userId) {
        this.userId = userId;
    }

    @Override
    public void save(FinancialAccount account) {
        Map<String, String> item = DynamoDbItem.fromAccount(userId, account);
        tableStorage.put(item.get("SK"), item);
    }

    @Override
    public Optional<FinancialAccount> findById(AccountId id) {
        String sk = "ACC#" + id.value();
        Map<String, String> item = tableStorage.get(sk);
        return Optional.ofNullable(item).map(DynamoDbItem::toAccount);
    }

    @Override
    public Optional<FinancialAccount> findByLastFourDigits(String lastFourDigits) {
        return tableStorage.values().stream()
            .filter(item -> "ACCOUNT".equals(item.get("entityType")))
            .filter(item -> lastFourDigits.equals(item.get("lastFourDigits")))
            .map(DynamoDbItem::toAccount)
            .findFirst();
    }

    @Override
    public void save(Transaction transaction) {
        Map<String, String> item = DynamoDbItem.fromTransaction(userId, transaction);
        tableStorage.put(item.get("SK"), item);
    }

    @Override
    public Optional<Transaction> findById(TransactionId id) {
        return tableStorage.values().stream()
            .filter(item -> "TRANSACTION".equals(item.get("entityType")))
            .filter(item -> id.value().equals(item.get("txnId")))
            .map(DynamoDbItem::toTransaction)
            .findFirst();
    }

    @Override
    public List<Transaction> findByAccountId(AccountId accountId) {
        List<Transaction> result = new ArrayList<>();
        for (Map<String, String> item : tableStorage.values()) {
            if ("TRANSACTION".equals(item.get("entityType")) && accountId.value().equals(item.get("accountId"))) {
                result.add(DynamoDbItem.toTransaction(item));
            }
        }
        return result;
    }

    @Override
    public List<Transaction> findByReconciliationStatus(ReconciliationStatus status) {
        return tableStorage.values().stream()
            .filter(item -> "TRANSACTION".equals(item.get("entityType")))
            .map(DynamoDbItem::toTransaction)
            .filter(txn -> txn.reconciliationStatus() == status || (status == ReconciliationStatus.NEEDS_REVIEW && txn.categoryId() == null))
            .collect(Collectors.toList());
    }

    @Override
    public List<Transaction> findByAccountIdAndWindow(AccountId accountId, LocalDateTime startTime, LocalDateTime endTime) {
        return tableStorage.values().stream()
            .filter(item -> "TRANSACTION".equals(item.get("entityType")))
            .map(DynamoDbItem::toTransaction)
            .filter(txn -> txn.accountId().equals(accountId))
            .filter(txn -> !txn.timestamp().isBefore(startTime) && !txn.timestamp().isAfter(endTime))
            .collect(Collectors.toList());
    }

    @Override
    public void delete(TransactionId id) {
        tableStorage.values().removeIf(item -> "TRANSACTION".equals(item.get("entityType")) && id.value().equals(item.get("txnId")));
    }
}
