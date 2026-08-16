package com.automaticexpense.tracker.domain;

import java.util.Objects;

public class PeerDebtEntry {
    private final String id;
    private final String contactName;
    private final Money amount;
    private final String description;
    private final boolean isLent; // true if user lent money, false if borrowed
    private boolean isSettled;

    public PeerDebtEntry(String id, String contactName, Money amount, String description, boolean isLent, boolean isSettled) {
        this.id = Objects.requireNonNull(id, "id cannot be null");
        this.contactName = Objects.requireNonNull(contactName, "contactName cannot be null");
        this.amount = Objects.requireNonNull(amount, "amount cannot be null");
        this.description = description;
        this.isLent = isLent;
        this.isSettled = isSettled;
    }

    public void settle() {
        this.isSettled = true;
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

    public String description() {
        return description;
    }

    public boolean isLent() {
        return isLent;
    }

    public boolean isSettled() {
        return isSettled;
    }
}
