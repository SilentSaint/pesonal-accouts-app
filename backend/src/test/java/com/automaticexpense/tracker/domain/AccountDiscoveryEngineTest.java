package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class AccountDiscoveryEngineTest {

    private final AccountDiscoveryEngine engine = new AccountDiscoveryEngine();

    @Test
    void shouldDiscoverAccountsAndAutoDeduplicate30DayHistory() {
        LocalDateTime baseTime = LocalDateTime.now().minusDays(10);

        ParsedTransactionEvent smsEvent = new ParsedTransactionEvent(
            new BigDecimal("1200.00"),
            "INR",
            TransactionType.DEBIT,
            "4321",
            "Amazon",
            baseTime
        );

        ParsedTransactionEvent emailEvent = new ParsedTransactionEvent(
            new BigDecimal("1200.00"),
            "INR",
            TransactionType.DEBIT,
            "4321",
            "Amazon",
            baseTime.plusMinutes(5)
        );

        BackfillResult result = engine.processHistoricalEvents(
            List.of(smsEvent),
            List.of(emailEvent),
            Collections.emptyList()
        );

        assertThat(result.discoveredAccounts()).hasSize(1);
        assertThat(result.discoveredAccounts().get(0).lastFourDigits()).isEqualTo("4321");
        assertThat(result.transactions()).hasSize(1);
        assertThat(result.transactions().get(0).reconciliationStatus()).isEqualTo(ReconciliationStatus.AUTO_MERGED);
    }
}
