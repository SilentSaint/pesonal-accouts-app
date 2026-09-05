package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class BillStatementTest {

    @Test
    void shouldInitializePendingBillStatement() {
        BillStatement bill = new BillStatement(
            "bill-1",
            new AccountId("acc-card-1"),
            "HDFC Regalia Credit Card",
            Money.of("42500.00", "INR"),
            Money.of("2500.00", "INR"),
            LocalDate.of(2026, 8, 20),
            LocalDate.of(2026, 9, 10)
        );

        assertThat(bill.id()).isEqualTo("bill-1");
        assertThat(bill.cardName()).isEqualTo("HDFC Regalia Credit Card");
        assertThat(bill.totalAmount()).isEqualTo(Money.of("42500.00", "INR"));
        assertThat(bill.minimumDue()).isEqualTo(Money.of("2500.00", "INR"));
        assertThat(bill.paidAmount()).isEqualTo(Money.zero("INR"));
        assertThat(bill.remainingDue()).isEqualTo(Money.of("42500.00", "INR"));
        assertThat(bill.status()).isEqualTo(BillStatus.PENDING);
        assertThat(bill.isPaid()).isFalse();
    }

    @Test
    void shouldRecordPaymentAndCloseBillWhenFullyPaid() {
        BillStatement bill = new BillStatement(
            "bill-2",
            new AccountId("acc-card-2"),
            "SBI SimplyCLICK",
            Money.of("15000.00", "INR"),
            Money.of("1000.00", "INR"),
            LocalDate.of(2026, 8, 15),
            LocalDate.of(2026, 9, 5)
        );

        bill.recordPayment(Money.of("15000.00", "INR"));

        assertThat(bill.paidAmount()).isEqualTo(Money.of("15000.00", "INR"));
        assertThat(bill.remainingDue()).isEqualTo(Money.zero("INR"));
        assertThat(bill.status()).isEqualTo(BillStatus.PAID);
        assertThat(bill.isPaid()).isTrue();
    }

    @Test
    void shouldTrackPartialPayments() {
        BillStatement bill = new BillStatement(
            "bill-3",
            new AccountId("acc-card-3"),
            "ICICI Sapphiro",
            Money.of("30000.00", "INR"),
            Money.of("2000.00", "INR"),
            LocalDate.of(2026, 8, 10),
            LocalDate.of(2026, 9, 1)
        );

        bill.recordPayment(Money.of("10000.00", "INR"));

        assertThat(bill.paidAmount()).isEqualTo(Money.of("10000.00", "INR"));
        assertThat(bill.remainingDue()).isEqualTo(Money.of("20000.00", "INR"));
        assertThat(bill.status()).isEqualTo(BillStatus.PENDING);
        assertThat(bill.isPaid()).isFalse();
    }

    @Test
    void shouldDetectOverdueStatus() {
        BillStatement bill = new BillStatement(
            "bill-4",
            new AccountId("acc-card-4"),
            "Axis Bank Card",
            Money.of("8000.00", "INR"),
            Money.of("500.00", "INR"),
            LocalDate.of(2026, 8, 1),
            LocalDate.of(2026, 8, 20)
        );

        assertThat(bill.isOverdue(LocalDate.of(2026, 8, 25))).isTrue();
        assertThat(bill.isOverdue(LocalDate.of(2026, 8, 15))).isFalse();
    }

    @Test
    void shouldPersistAnOverdueLifecycleStateAfterTheDueDate() {
        BillStatement bill = new BillStatement(
            "bill-5",
            new AccountId("acc-card-5"),
            "Axis Bank Card",
            Money.of("8000.00", "INR"),
            Money.of("500.00", "INR"),
            LocalDate.of(2026, 8, 1),
            LocalDate.of(2026, 8, 20)
        );

        assertThat(bill.updateLifecycleStatus(LocalDate.of(2026, 8, 21))).isTrue();
        assertThat(bill.status()).isEqualTo(BillStatus.OVERDUE);
    }
}
