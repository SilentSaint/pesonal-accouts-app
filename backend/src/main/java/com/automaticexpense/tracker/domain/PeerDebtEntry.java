package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Objects;

public class PeerDebtEntry {
    private final String id;
    private final String contactName;
    private final Money amount;
    private Money settledAmount;
    private final String description;
    private final boolean isLent; // true if user lent money, false if borrowed
    private boolean isSettled;
    private final String transactionId;
    private final LocalDateTime createdAt;
    private final LocalDate dueDate;

    public PeerDebtEntry(String id, String contactName, Money amount, String description, boolean isLent, boolean isSettled) {
        this(id, contactName, amount, Money.zero(amount.currency()), description, isLent, isSettled, null, LocalDateTime.now(), null);
    }

    public PeerDebtEntry(
        String id,
        String contactName,
        Money amount,
        Money settledAmount,
        String description,
        boolean isLent,
        boolean isSettled,
        String transactionId,
        LocalDateTime createdAt,
        LocalDate dueDate
    ) {
        this.id = Objects.requireNonNull(id, "id cannot be null");
        this.contactName = Objects.requireNonNull(contactName, "contactName cannot be null");
        this.amount = Objects.requireNonNull(amount, "amount cannot be null");
        this.settledAmount = settledAmount != null ? settledAmount : Money.zero(amount.currency());
        this.description = description != null ? description : "";
        this.isLent = isLent;
        this.isSettled = isSettled;
        this.transactionId = transactionId;
        this.createdAt = createdAt != null ? createdAt : LocalDateTime.now();
        this.dueDate = dueDate;
    }

    public void settle() {
        this.settledAmount = this.amount;
        this.isSettled = true;
    }

    public void partiallySettle(Money payment) {
        Objects.requireNonNull(payment, "payment cannot be null");
        if (payment.amount().signum() <= 0) {
            throw new IllegalArgumentException("Settlement payment must be positive");
        }
        this.settledAmount = this.settledAmount.add(payment);
        if (this.settledAmount.isGreaterThanOrEqualTo(this.amount)) {
            this.settledAmount = this.amount;
            this.isSettled = true;
        }
    }

    public Money remainingAmount() {
        return this.amount.subtract(this.settledAmount);
    }

    public String id() {
        return id;
    }

    public String contactName() {
        return contactName;
    }

    public Money amount() {
        return amount;
    }

    public Money settledAmount() {
        return settledAmount;
    }

    public String description() {
        return description;
    }

    public boolean isLent() {
        return isLent;
    }

    public boolean isSettled() {
        return isSettled;
    }

    public String transactionId() {
        return transactionId;
    }

    public LocalDateTime createdAt() {
        return createdAt;
    }

    public LocalDate dueDate() {
        return dueDate;
    }
}
