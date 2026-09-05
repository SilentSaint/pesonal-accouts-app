package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class LoanAccountTest {

    @Test
    void shouldInitializeActiveLoanAccount() {
        LoanAccount loan = new LoanAccount(
            "loan-1",
            "HDFC Home Loan",
            "HDFC Bank",
            Money.of("5000000.00", "INR"),
            Money.of("45000.00", "INR"),
            8.5,
            240,
            0,
            LocalDate.of(2026, 9, 5)
        );

        assertThat(loan.id()).isEqualTo("loan-1");
        assertThat(loan.loanName()).isEqualTo("HDFC Home Loan");
        assertThat(loan.lenderName()).isEqualTo("HDFC Bank");
        assertThat(loan.principalAmount()).isEqualTo(Money.of("5000000.00", "INR"));
        assertThat(loan.remainingPrincipal()).isEqualTo(Money.of("5000000.00", "INR"));
        assertThat(loan.emiAmount()).isEqualTo(Money.of("45000.00", "INR"));
        assertThat(loan.totalInstallments()).isEqualTo(240);
        assertThat(loan.completedInstallments()).isEqualTo(0);
        assertThat(loan.remainingInstallments()).isEqualTo(240);
        assertThat(loan.status()).isEqualTo(LoanStatus.ACTIVE);
        assertThat(loan.nextDueDate()).isEqualTo(LocalDate.of(2026, 9, 5));
    }

    @Test
    void shouldRecordEmiPaymentAndAdvanceDueDate() {
        LoanAccount loan = new LoanAccount(
            "loan-2",
            "SBI Auto Loan",
            "SBI",
            Money.of("600000.00", "INR"),
            Money.of("15000.00", "INR"),
            9.0,
            48,
            10,
            LocalDate.of(2026, 9, 10)
        );

        loan.recordEmiPayment(Money.of("15000.00", "INR"));

        assertThat(loan.completedInstallments()).isEqualTo(11);
        assertThat(loan.remainingInstallments()).isEqualTo(37);
        assertThat(loan.nextDueDate()).isEqualTo(LocalDate.of(2026, 10, 10));
        assertThat(loan.status()).isEqualTo(LoanStatus.ACTIVE);
    }

    @Test
    void shouldCloseLoanWhenAllInstallmentsCompleted() {
        LoanAccount loan = new LoanAccount(
            "loan-3",
            "Personal Loan",
            "Axis Bank",
            Money.of("100000.00", "INR"),
            Money.of("10000.00", "INR"),
            11.5,
            12,
            11,
            LocalDate.of(2026, 9, 1)
        );

        loan.recordEmiPayment(Money.of("10000.00", "INR"));

        assertThat(loan.completedInstallments()).isEqualTo(12);
        assertThat(loan.remainingInstallments()).isEqualTo(0);
        assertThat(loan.status()).isEqualTo(LoanStatus.CLOSED);
        assertThat(loan.isClosed()).isTrue();
    }
}
