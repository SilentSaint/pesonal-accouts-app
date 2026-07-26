package com.automaticexpense.tracker.domain;

import java.time.LocalDateTime;
import java.util.Objects;

public class Transaction {
    private final TransactionId id;
    private final Money amount;
    private final TransactionType type;
    private final LocalDateTime timestamp;
    private final String merchantName;
    private final AccountId accountId;
    private final String categoryId;
    private final IngestionSource ingestionSource;
    private final ReconciliationStatus reconciliationStatus;
    private Money netPersonalExpense;

    public Transaction(TransactionId id, Money amount, TransactionType type, LocalDateTime timestamp, String merchantName, AccountId accountId, String categoryId, IngestionSource ingestionSource, ReconciliationStatus reconciliationStatus, Money netPersonalExpense) {
        this.id = Objects.requireNonNull(id, "id cannot be null");
        this.amount = Objects.requireNonNull(amount, "amount cannot be null");
        this.type = Objects.requireNonNull(type, "type cannot be null");
        this.timestamp = Objects.requireNonNull(timestamp, "timestamp cannot be null");
        this.merchantName = merchantName != null ? merchantName : "UNKNOWN";
        this.accountId = Objects.requireNonNull(accountId, "accountId cannot be null");
        this.categoryId = categoryId;
        this.ingestionSource = Objects.requireNonNull(ingestionSource, "ingestionSource cannot be null");
        this.reconciliationStatus = Objects.requireNonNull(reconciliationStatus, "reconciliationStatus cannot be null");
        this.netPersonalExpense = netPersonalExpense != null ? netPersonalExpense : amount;
    }

    public TransactionId id() {
        return id;
    }

    public Money amount() {
        return amount;
    }

    public TransactionType type() {
        return type;
    }

    public LocalDateTime timestamp() {
        return timestamp;
    }

    public String merchantName() {
        return merchantName;
    }

    public AccountId accountId() {
        return accountId;
    }

    public String categoryId() {
        return categoryId;
    }

    public IngestionSource ingestionSource() {
        return ingestionSource;
    }

    public ReconciliationStatus reconciliationStatus() {
        return reconciliationStatus;
    }

    public Money netPersonalExpense() {
        return netPersonalExpense;
    }

    public void setNetPersonalExpense(Money netPersonalExpense) {
        this.netPersonalExpense = Objects.requireNonNull(netPersonalExpense, "netPersonalExpense cannot be null");
    }
}
