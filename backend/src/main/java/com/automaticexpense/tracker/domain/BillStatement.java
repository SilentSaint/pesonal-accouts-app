package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.LinkedHashSet;
import java.util.Objects;
import java.util.Set;

public class BillStatement {
    private final String id;
    private final AccountId accountId;
    private final String cardName;
    private final Money totalAmount;
    private final Money minimumDue;
    private Money paidAmount;
    private final LocalDate statementDate;
    private final LocalDate dueDate;
    private BillStatus status;
    private final Set<String> recordedPaymentTransactionIds;
    private final long version;

    public BillStatement(
        String id,
        AccountId accountId,
        String cardName,
        Money totalAmount,
        Money minimumDue,
        LocalDate statementDate,
        LocalDate dueDate
    ) {
        this(
            id,
            accountId,
            cardName,
            totalAmount,
            minimumDue,
            Money.zero(totalAmount.currency()),
            statementDate,
            dueDate,
            BillStatus.PENDING,
            Set.of(),
            0
        );
    }

    public BillStatement(
        String id,
        AccountId accountId,
        String cardName,
        Money totalAmount,
        Money minimumDue,
        Money paidAmount,
        LocalDate statementDate,
        LocalDate dueDate,
        BillStatus status
    ) {
        this(
            id, accountId, cardName, totalAmount, minimumDue, paidAmount, statementDate, dueDate, status, Set.of(), 0
        );
    }

    public BillStatement(
        String id,
        AccountId accountId,
        String cardName,
        Money totalAmount,
        Money minimumDue,
        Money paidAmount,
        LocalDate statementDate,
        LocalDate dueDate,
        BillStatus status,
        Set<String> recordedPaymentTransactionIds,
        long version
    ) {
        this.id = Objects.requireNonNull(id, "id cannot be null");
        this.accountId = Objects.requireNonNull(accountId, "accountId cannot be null");
        this.cardName = cardName != null ? cardName : "Credit Card (" + accountId.value() + ")";
        this.totalAmount = Objects.requireNonNull(totalAmount, "totalAmount cannot be null");
        this.minimumDue = Objects.requireNonNull(minimumDue, "minimumDue cannot be null");
        this.paidAmount = paidAmount != null ? paidAmount : Money.zero(totalAmount.currency());
        this.statementDate = statementDate != null ? statementDate : LocalDate.now().minusDays(20);
        this.dueDate = Objects.requireNonNull(dueDate, "dueDate cannot be null");
        this.status = status != null ? status : BillStatus.PENDING;
        this.recordedPaymentTransactionIds = new LinkedHashSet<>(
            Objects.requireNonNull(recordedPaymentTransactionIds, "recordedPaymentTransactionIds cannot be null")
        );
        this.version = version;
    }

    public void recordPayment(Money payment) {
        recordPayment("manual-" + java.util.UUID.randomUUID(), payment);
    }

    public boolean recordPayment(String paymentTransactionId, Money payment) {
        Objects.requireNonNull(paymentTransactionId, "paymentTransactionId cannot be null");
        Objects.requireNonNull(payment, "payment cannot be null");
        if (!payment.currency().equalsIgnoreCase(totalAmount.currency())) {
            throw new IllegalArgumentException("Payment currency must match the statement currency");
        }
        if (payment.amount().signum() <= 0) {
            throw new IllegalArgumentException("Payment amount must be positive");
        }
        if (!recordedPaymentTransactionIds.add(paymentTransactionId)) {
            return false;
        }
        this.paidAmount = this.paidAmount.add(payment);
        if (this.paidAmount.isGreaterThanOrEqualTo(this.totalAmount)) {
            this.status = BillStatus.PAID;
        }
        return true;
    }

    public void markPaid() {
        this.paidAmount = this.totalAmount;
        this.status = BillStatus.PAID;
    }

    public Money remainingDue() {
        if (this.paidAmount.isGreaterThanOrEqualTo(this.totalAmount)) {
            return Money.zero(this.totalAmount.currency());
        }
        return this.totalAmount.subtract(this.paidAmount);
    }

    public boolean isOverdue(LocalDate today) {
        return this.status == BillStatus.OVERDUE || (this.status != BillStatus.PAID && today.isAfter(this.dueDate));
    }

    public boolean isPaid() {
        return this.status == BillStatus.PAID;
    }

    public String id() {
        return id;
    }

    public AccountId accountId() {
        return accountId;
    }

    public String cardName() {
        return cardName;
    }

    public Money totalAmount() {
        return totalAmount;
    }

    public Money minimumDue() {
        return minimumDue;
    }

    public Money paidAmount() {
        return paidAmount;
    }

    public LocalDate statementDate() {
        return statementDate;
    }

    public YearMonth billingCycle() {
        return YearMonth.from(statementDate);
    }

    public LocalDate dueDate() {
        return dueDate;
    }

    public BillStatus status() {
        return status;
    }

    public Set<String> recordedPaymentTransactionIds() {
        return Set.copyOf(recordedPaymentTransactionIds);
    }

    public long version() {
        return version;
    }

    public BillStatement withStatementTerms(
        String updatedCardName,
        Money updatedTotalAmount,
        Money updatedMinimumDue,
        LocalDate updatedStatementDate,
        LocalDate updatedDueDate
    ) {
        return new BillStatement(
            id,
            accountId,
            updatedCardName,
            updatedTotalAmount,
            updatedMinimumDue,
            paidAmount,
            updatedStatementDate,
            updatedDueDate,
            status,
            recordedPaymentTransactionIds,
            version
        );
    }

    public BillStatement withIncrementedVersion() {
        return new BillStatement(
            id,
            accountId,
            cardName,
            totalAmount,
            minimumDue,
            paidAmount,
            statementDate,
            dueDate,
            status,
            recordedPaymentTransactionIds,
            version + 1
        );
    }

    public boolean updateLifecycleStatus(LocalDate today) {
        Objects.requireNonNull(today, "today cannot be null");
        if (status != BillStatus.PAID && today.isAfter(dueDate) && status != BillStatus.OVERDUE) {
            status = BillStatus.OVERDUE;
            return true;
        }
        return false;
    }
}
