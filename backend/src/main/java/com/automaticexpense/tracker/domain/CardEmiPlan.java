package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.Objects;

public class CardEmiPlan {
    private final String id;
    private final String cardAccountId;
    private final String merchantName;
    private final Money totalPrincipal;
    private final Money monthlyInstallment;
    private final double interestRatePercent;
    private final int totalTenureMonths;
    private int completedInstallments;
    private LocalDate nextDueDate;
    private EmiPlanStatus status;

    public CardEmiPlan(
        String id,
        String cardAccountId,
        String merchantName,
        Money totalPrincipal,
        Money monthlyInstallment,
        double interestRatePercent,
        int totalTenureMonths,
        int completedInstallments,
        LocalDate nextDueDate
    ) {
        this(
            id,
            cardAccountId,
            merchantName,
            totalPrincipal,
            monthlyInstallment,
            interestRatePercent,
            totalTenureMonths,
            completedInstallments,
            nextDueDate,
            EmiPlanStatus.ACTIVE
        );
    }

    public CardEmiPlan(
        String id,
        String cardAccountId,
        String merchantName,
        Money totalPrincipal,
        Money monthlyInstallment,
        double interestRatePercent,
        int totalTenureMonths,
        int completedInstallments,
        LocalDate nextDueDate,
        EmiPlanStatus status
    ) {
        this.id = Objects.requireNonNull(id, "id cannot be null");
        this.cardAccountId = Objects.requireNonNull(cardAccountId, "cardAccountId cannot be null");
        this.merchantName = Objects.requireNonNull(merchantName, "merchantName cannot be null");
        this.totalPrincipal = Objects.requireNonNull(totalPrincipal, "totalPrincipal cannot be null");
        this.monthlyInstallment = Objects.requireNonNull(monthlyInstallment, "monthlyInstallment cannot be null");
        this.interestRatePercent = interestRatePercent;
        this.totalTenureMonths = totalTenureMonths;
        this.completedInstallments = completedInstallments;
        this.nextDueDate = nextDueDate != null ? nextDueDate : LocalDate.now().plusMonths(1);
        this.status = status != null ? status : (completedInstallments >= totalTenureMonths ? EmiPlanStatus.COMPLETED : EmiPlanStatus.ACTIVE);
    }

    public void recordInstallment() {
        if (this.completedInstallments < this.totalTenureMonths) {
            this.completedInstallments++;
        }
        if (this.nextDueDate != null) {
            this.nextDueDate = this.nextDueDate.plusMonths(1);
        }
        if (this.completedInstallments >= this.totalTenureMonths) {
            this.status = EmiPlanStatus.COMPLETED;
        }
    }

    public int remainingInstallments() {
        return Math.max(0, totalTenureMonths - completedInstallments);
    }

    public boolean isCompleted() {
        return status == EmiPlanStatus.COMPLETED;
    }

    public String id() {
        return id;
    }

    public String cardAccountId() {
        return cardAccountId;
    }

    public String merchantName() {
        return merchantName;
    }

    public Money totalPrincipal() {
        return totalPrincipal;
    }

    public Money monthlyInstallment() {
        return monthlyInstallment;
    }

    public double interestRatePercent() {
        return interestRatePercent;
    }

    public int totalTenureMonths() {
        return totalTenureMonths;
    }

    public int completedInstallments() {
        return completedInstallments;
    }

    public LocalDate nextDueDate() {
        return nextDueDate;
    }

    public EmiPlanStatus status() {
        return status;
    }
}
