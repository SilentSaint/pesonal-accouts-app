package com.automaticexpense.tracker.domain;

import java.util.Objects;

public class FinancialAccount {
    private final AccountId id;
    private final String name;
    private final AccountType type;
    private final String lastFourDigits;
    private final String currency;
    private Money currentBalance;

    public FinancialAccount(AccountId id, String name, AccountType type, String lastFourDigits, String currency, Money currentBalance) {
        this.id = Objects.requireNonNull(id, "id cannot be null");
        this.name = Objects.requireNonNull(name, "name cannot be null");
        this.type = Objects.requireNonNull(type, "type cannot be null");
        this.lastFourDigits = Objects.requireNonNull(lastFourDigits, "lastFourDigits cannot be null");
        this.currency = Objects.requireNonNull(currency, "currency cannot be null");
        this.currentBalance = Objects.requireNonNull(currentBalance, "currentBalance cannot be null");
    }

    public AccountId id() {
        return id;
    }

    public String name() {
        return name;
    }

    public AccountType type() {
        return type;
    }

    public String lastFourDigits() {
        return lastFourDigits;
    }

    public String currency() {
        return currency;
    }

    public Money currentBalance() {
        return currentBalance;
    }

    public void applyTransaction(Money amount, TransactionType transactionType) {
        if (transactionType == TransactionType.CREDIT) {
            this.currentBalance = this.currentBalance.add(amount);
        } else {
            this.currentBalance = this.currentBalance.subtract(amount);
        }
    }
}
