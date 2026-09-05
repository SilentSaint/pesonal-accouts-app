package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class PeerDebtEntryTest {

    @Test
    void shouldCreateUnsettledLentDebtEntry() {
        PeerDebtEntry debt = new PeerDebtEntry(
            "debt-1",
            "Alice",
            Money.of("100.00", "USD"),
            "Dinner split",
            true,
            false
        );

        assertThat(debt.id()).isEqualTo("debt-1");
        assertThat(debt.contactName()).isEqualTo("Alice");
        assertThat(debt.amount()).isEqualTo(Money.of("100.00", "USD"));
        assertThat(debt.settledAmount()).isEqualTo(Money.zero("USD"));
        assertThat(debt.remainingAmount()).isEqualTo(Money.of("100.00", "USD"));
        assertThat(debt.isLent()).isTrue();
        assertThat(debt.isSettled()).isFalse();
    }

    @Test
    void shouldSettleDebtCompletely() {
        PeerDebtEntry debt = new PeerDebtEntry(
            "debt-2",
            "Bob",
            Money.of("50.00", "USD"),
            "Movie ticket",
            false,
            false
        );

        debt.settle();

        assertThat(debt.isSettled()).isTrue();
        assertThat(debt.settledAmount()).isEqualTo(Money.of("50.00", "USD"));
        assertThat(debt.remainingAmount()).isEqualTo(Money.zero("USD"));
    }

    @Test
    void shouldHandlePartialSettlements() {
        PeerDebtEntry debt = new PeerDebtEntry(
            "debt-3",
            "Charlie",
            Money.of("100.00", "USD"),
            "Concert ticket",
            true,
            false
        );

        debt.partiallySettle(Money.of("40.00", "USD"));
        assertThat(debt.isSettled()).isFalse();
        assertThat(debt.settledAmount()).isEqualTo(Money.of("40.00", "USD"));
        assertThat(debt.remainingAmount()).isEqualTo(Money.of("60.00", "USD"));

        debt.partiallySettle(Money.of("60.00", "USD"));
        assertThat(debt.isSettled()).isTrue();
        assertThat(debt.settledAmount()).isEqualTo(Money.of("100.00", "USD"));
        assertThat(debt.remainingAmount()).isEqualTo(Money.zero("USD"));
    }

    @Test
    void shouldRejectInvalidSettlementAmount() {
        PeerDebtEntry debt = new PeerDebtEntry(
            "debt-4",
            "Dave",
            Money.of("50.00", "USD"),
            "Groceries",
            true,
            false
        );

        assertThatThrownBy(() -> debt.partiallySettle(Money.of("-10.00", "USD")))
            .isInstanceOf(IllegalArgumentException.class);
    }
}
