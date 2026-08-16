package com.automaticexpense.tracker.domain;

import java.util.Objects;

public class LoanAccount {
    private final String id;
    private final String lenderName;
    private final Money principalAmount;
    private final Money emiAmount;
    private final int totalInstallments;
    private int completedInstallments;

    public LoanAccount(String id, String lenderName, Money principalAmount, Money emiAmount, int totalInstallments, int completedInstallments) {
        this.id = Objects.requireNonNull(id, "id cannot be null");
        this.lenderName = Objects.requireNonNull(lenderName, "lenderName cannot be null");
        this.principalAmount = Objects.requireNonNull(principalAmount, "principalAmount cannot be null");
        this.emiAmount = Objects.requireNonNull(emiAmount, "emiAmount cannot be null");
        this.totalInstallments = totalInstallments;
        this.completedInstallments = completedInstallments;
    }

    public void recordEmiDebit() {
        if (completedInstallments < totalInstallments) {
            completedInstallments++;
        }
    }

    public String id() {
        return id;
    }

    public String lenderName() {
        return lenderName;
    }

    public Money principalAmount() {
        return principalAmount;
    }

    public Money emiAmount() {
        return emiAmount;
    }

    public int totalInstallments() {
        return totalInstallments;
    }

    public int completedInstallments() {
        return completedInstallments;
    }
}
