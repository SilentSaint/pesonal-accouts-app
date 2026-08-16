package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.Objects;

public class BillStatement {
    private final String id;
    private final AccountId accountId;
    private final Money totalAmount;
    private final Money minimumDue;
    private final LocalDate dueDate;
    private boolean isPaid;

    public BillStatement(String id, AccountId accountId, Money totalAmount, Money minimumDue, LocalDate dueDate, boolean isPaid) {
        this.id = Objects.requireNonNull(id, "id cannot be null");
        this.accountId = Objects.requireNonNull(accountId, "accountId cannot be null");
        this.totalAmount = Objects.requireNonNull(totalAmount, "totalAmount cannot be null");
        this.minimumDue = Objects.requireNonNull(minimumDue, "minimumDue cannot be null");
        this.dueDate = Objects.requireNonNull(dueDate, "dueDate cannot be null");
        this.isPaid = isPaid;
    }

    public void markPaid() {
        this.isPaid = true;
    }

    public String id() {
        return id;
    }

    public AccountId accountId() {
        return accountId;
    }

    public Money totalAmount() {
        return totalAmount;
    }

    public Money minimumDue() {
        return minimumDue;
    }

    public LocalDate dueDate() {
        return dueDate;
    }

    public boolean isPaid() {
        return isPaid;
    }
}
