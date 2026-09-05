package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class IncomeSourceTest {

    @Test
    void confirmingAnIncomeSuggestionIsIdempotentAndKeepsItsTransactionEvidence() {
        IncomeSource suggestion = IncomeSource.suggested(
            "income-1",
            "Acme Payroll",
            IncomeSourceType.FIXED,
            Money.of("75000.00", "INR"),
            IncomeCadence.MONTHLY,
            LocalDate.of(2026, 1, 1),
            null,
            new AccountId("salary-account"),
            Set.of(new TransactionId("credit-jan"), new TransactionId("credit-feb")),
            "acme-payroll-monthly"
        );

        IncomeSource confirmedOnce = suggestion.confirm();
        IncomeSource confirmedTwice = confirmedOnce.confirm();

        assertThat(confirmedTwice.confirmationStatus()).isEqualTo(IncomeConfirmationStatus.CONFIRMED);
        assertThat(confirmedTwice.sourceTransactionIds())
            .containsExactlyInAnyOrder(new TransactionId("credit-jan"), new TransactionId("credit-feb"));
        assertThat(confirmedTwice.suggestionKey()).isEqualTo("acme-payroll-monthly");
    }
}
