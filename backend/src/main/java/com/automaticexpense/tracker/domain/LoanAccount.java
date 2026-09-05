package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.Objects;

public class LoanAccount {
    private final String id;
    private final String loanName;
    private final String lenderName;
    private final Money principalAmount;
    private Money remainingPrincipal;
    private final Money emiAmount;
    private final double interestRatePercent;
    private final int totalInstallments;
    private int completedInstallments;
    private LocalDate nextDueDate;
    private LoanStatus status;

    public LoanAccount(
        String id,
        String loanName,
        String lenderName,
        Money principalAmount,
        Money emiAmount,
        double interestRatePercent,
        int totalInstallments,
        int completedInstallments,
        LocalDate nextDueDate
    ) {
        this(
            id,
            loanName,
            lenderName,
            principalAmount,
            principalAmount,
            emiAmount,
            interestRatePercent,
            totalInstallments,
            completedInstallments,
            nextDueDate,
            LoanStatus.ACTIVE
        );
    }

    public LoanAccount(
        String id,
        String loanName,
        String lenderName,
        Money principalAmount,
        Money remainingPrincipal,
        Money emiAmount,
        double interestRatePercent,
        int totalInstallments,
        int completedInstallments,
        LocalDate nextDueDate,
        LoanStatus status
    ) {
        this.id = Objects.requireNonNull(id, "id cannot be null");
        this.loanName = loanName != null ? loanName : lenderName + " Loan";
        this.lenderName = Objects.requireNonNull(lenderName, "lenderName cannot be null");
        this.principalAmount = Objects.requireNonNull(principalAmount, "principalAmount cannot be null");
        this.remainingPrincipal = remainingPrincipal != null ? remainingPrincipal : principalAmount;
        this.emiAmount = Objects.requireNonNull(emiAmount, "emiAmount cannot be null");
        this.interestRatePercent = interestRatePercent;
        this.totalInstallments = totalInstallments;
        this.completedInstallments = completedInstallments;
        this.nextDueDate = nextDueDate != null ? nextDueDate : LocalDate.now().plusMonths(1);
        this.status = status != null ? status : (completedInstallments >= totalInstallments ? LoanStatus.CLOSED : LoanStatus.ACTIVE);
    }

    public void recordEmiPayment(Money payment) {
        Objects.requireNonNull(payment, "payment cannot be null");
        if (this.completedInstallments < this.totalInstallments) {
            this.completedInstallments++;
        }
        if (this.nextDueDate != null) {
            this.nextDueDate = this.nextDueDate.plusMonths(1);
        }
        if (this.completedInstallments >= this.totalInstallments) {
            this.status = LoanStatus.CLOSED;
            this.remainingPrincipal = Money.zero(this.principalAmount.currency());
        }
    }

    public int remainingInstallments() {
        return Math.max(0, totalInstallments - completedInstallments);
    }

    public boolean isClosed() {
        return status == LoanStatus.CLOSED;
    }

    public String id() {
        return id;
    }

    public String loanName() {
        return loanName;
    }

    public String lenderName() {
        return lenderName;
    }

    public Money principalAmount() {
        return principalAmount;
    }

    public Money remainingPrincipal() {
        return remainingPrincipal;
    }

    public Money emiAmount() {
        return emiAmount;
    }

    public double interestRatePercent() {
        return interestRatePercent;
    }

    public int totalInstallments() {
        return totalInstallments;
    }

    public int completedInstallments() {
        return completedInstallments;
    }

    public LocalDate nextDueDate() {
        return nextDueDate;
    }

    public LoanStatus status() {
        return status;
    }
}
