package com.automaticexpense.tracker.domain;

import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.Objects;
import java.util.Set;

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
    private final String subCategory;
    private final String accountMask;
    private final String referenceNumber;
    private final String rawSnippet;
    private final String transferCounterpartMask;
    private final Set<IngestionSource> ingestionSources;
    private final TransactionId potentialDuplicateOfTransactionId;

    public Transaction(TransactionId id, Money amount, TransactionType type, LocalDateTime timestamp, String merchantName, AccountId accountId, String categoryId, IngestionSource ingestionSource, ReconciliationStatus reconciliationStatus, Money netPersonalExpense) {
        this(
            id, amount, type, timestamp, merchantName, accountId, categoryId,
            null, ingestionSource, reconciliationStatus, netPersonalExpense,
            null, null, null, null
        );
    }

    public Transaction(
        TransactionId id,
        Money amount,
        TransactionType type,
        LocalDateTime timestamp,
        String merchantName,
        AccountId accountId,
        String categoryId,
        String subCategory,
        IngestionSource ingestionSource,
        ReconciliationStatus reconciliationStatus,
        Money netPersonalExpense,
        String accountMask,
        String referenceNumber,
        String rawSnippet,
        String transferCounterpartMask
    ) {
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
        this.subCategory = subCategory;
        this.accountMask = accountMask;
        this.referenceNumber = referenceNumber;
        this.rawSnippet = rawSnippet;
        this.transferCounterpartMask = transferCounterpartMask;
        this.ingestionSources = Set.of(ingestionSource);
        this.potentialDuplicateOfTransactionId = null;
    }

    private Transaction(
        TransactionId id,
        Money amount,
        TransactionType type,
        LocalDateTime timestamp,
        String merchantName,
        AccountId accountId,
        String categoryId,
        String subCategory,
        IngestionSource ingestionSource,
        ReconciliationStatus reconciliationStatus,
        Money netPersonalExpense,
        String accountMask,
        String referenceNumber,
        String rawSnippet,
        String transferCounterpartMask,
        Set<IngestionSource> ingestionSources,
        TransactionId potentialDuplicateOfTransactionId
    ) {
        this.id = Objects.requireNonNull(id, "id cannot be null");
        this.amount = Objects.requireNonNull(amount, "amount cannot be null");
        this.type = Objects.requireNonNull(type, "type cannot be null");
        this.timestamp = Objects.requireNonNull(timestamp, "timestamp cannot be null");
        this.merchantName = merchantName != null ? merchantName : "UNKNOWN";
        this.accountId = Objects.requireNonNull(accountId, "accountId cannot be null");
        this.categoryId = categoryId;
        this.subCategory = subCategory;
        this.ingestionSource = Objects.requireNonNull(ingestionSource, "ingestionSource cannot be null");
        this.reconciliationStatus = Objects.requireNonNull(reconciliationStatus, "reconciliationStatus cannot be null");
        this.netPersonalExpense = netPersonalExpense != null ? netPersonalExpense : amount;
        this.accountMask = accountMask;
        this.referenceNumber = referenceNumber;
        this.rawSnippet = rawSnippet;
        this.transferCounterpartMask = transferCounterpartMask;
        this.ingestionSources = Set.copyOf(Objects.requireNonNull(ingestionSources, "ingestionSources cannot be null"));
        this.potentialDuplicateOfTransactionId = potentialDuplicateOfTransactionId;
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

    public String subCategory() {
        return subCategory;
    }

    public String accountMask() {
        return accountMask;
    }

    public String referenceNumber() {
        return referenceNumber;
    }

    public String rawSnippet() {
        return rawSnippet;
    }

    public String transferCounterpartMask() {
        return transferCounterpartMask;
    }

    public Set<IngestionSource> ingestionSources() {
        return ingestionSources;
    }

    public TransactionId potentialDuplicateOfTransactionId() {
        return potentialDuplicateOfTransactionId;
    }

    public Transaction withReconciliationStatus(ReconciliationStatus status) {
        return copy(status, categoryId, subCategory, potentialDuplicateOfTransactionId, ingestionSources);
    }

    public Transaction withPotentialDuplicateOf(TransactionId canonicalTransactionId) {
        return copy(
            ReconciliationStatus.NEEDS_REVIEW,
            categoryId,
            subCategory,
            Objects.requireNonNull(canonicalTransactionId, "canonicalTransactionId cannot be null"),
            ingestionSources
        );
    }

    public Transaction enrichedWith(IngestionSource source) {
        EnumSet<IngestionSource> sources = EnumSet.copyOf(ingestionSources);
        sources.add(Objects.requireNonNull(source, "source cannot be null"));
        return copy(ReconciliationStatus.AUTO_MERGED, categoryId, subCategory, null, sources);
    }

    public Transaction withIngestionSources(Set<IngestionSource> sources) {
        return copy(reconciliationStatus, categoryId, subCategory, potentialDuplicateOfTransactionId, sources);
    }

    public Transaction confirmedAsSeparate(String updatedCategory) {
        return copy(ReconciliationStatus.CONFIRMED, updatedCategory, subCategory, null, ingestionSources);
    }

    private Transaction copy(
        ReconciliationStatus status,
        String updatedCategory,
        String updatedSubCategory,
        TransactionId duplicateOf,
        Set<IngestionSource> sources
    ) {
        return new Transaction(
            id, amount, type, timestamp, merchantName, accountId, updatedCategory,
            updatedSubCategory, ingestionSource, status, netPersonalExpense,
            accountMask, referenceNumber, rawSnippet, transferCounterpartMask,
            sources, duplicateOf
        );
    }

    public Transaction confirmedWithCategory(String category) {
        return confirmedWithCategory(category, subCategory);
    }

    public Transaction confirmedWithCategory(String category, String updatedSubCategory) {
        return copy(ReconciliationStatus.CONFIRMED, category, updatedSubCategory, null, ingestionSources);
    }
}
