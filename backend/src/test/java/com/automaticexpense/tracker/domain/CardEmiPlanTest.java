package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class CardEmiPlanTest {

    @Test
    void shouldInitializeActiveCardEmiPlan() {
        CardEmiPlan plan = new CardEmiPlan(
            "emi-101",
            "acc-card-1",
            "Amazon India - Laptop",
            Money.of("60000.00", "INR"),
            Money.of("10500.00", "INR"),
            14.0,
            6,
            0,
            LocalDate.of(2026, 9, 15)
        );

        assertThat(plan.id()).isEqualTo("emi-101");
        assertThat(plan.cardAccountId()).isEqualTo("acc-card-1");
        assertThat(plan.merchantName()).isEqualTo("Amazon India - Laptop");
        assertThat(plan.totalPrincipal()).isEqualTo(Money.of("60000.00", "INR"));
        assertThat(plan.monthlyInstallment()).isEqualTo(Money.of("10500.00", "INR"));
        assertThat(plan.interestRatePercent()).isEqualTo(14.0);
        assertThat(plan.totalTenureMonths()).isEqualTo(6);
        assertThat(plan.completedInstallments()).isEqualTo(0);
        assertThat(plan.remainingInstallments()).isEqualTo(6);
        assertThat(plan.status()).isEqualTo(EmiPlanStatus.ACTIVE);
    }

    @Test
    void shouldRecordInstallmentAndAdvanceDueDate() {
        CardEmiPlan plan = new CardEmiPlan(
            "emi-102",
            "acc-card-1",
            "IKEA Furniture",
            Money.of("36000.00", "INR"),
            Money.of("3200.00", "INR"),
            13.5,
            12,
            3,
            LocalDate.of(2026, 9, 20)
        );

        plan.recordInstallment();

        assertThat(plan.completedInstallments()).isEqualTo(4);
        assertThat(plan.remainingInstallments()).isEqualTo(8);
        assertThat(plan.nextDueDate()).isEqualTo(LocalDate.of(2026, 10, 20));
        assertThat(plan.status()).isEqualTo(EmiPlanStatus.ACTIVE);
    }

    @Test
    void shouldCompleteEmiPlanWhenAllInstallmentsPaid() {
        CardEmiPlan plan = new CardEmiPlan(
            "emi-103",
            "acc-card-1",
            "Croma Electronics",
            Money.of("15000.00", "INR"),
            Money.of("5200.00", "INR"),
            12.0,
            3,
            2,
            LocalDate.of(2026, 9, 1)
        );

        plan.recordInstallment();

        assertThat(plan.completedInstallments()).isEqualTo(3);
        assertThat(plan.remainingInstallments()).isEqualTo(0);
        assertThat(plan.status()).isEqualTo(EmiPlanStatus.COMPLETED);
        assertThat(plan.isCompleted()).isTrue();
    }
}
