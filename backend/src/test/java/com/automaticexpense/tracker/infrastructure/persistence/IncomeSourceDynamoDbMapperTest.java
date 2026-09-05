package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IncomeCadence;
import com.automaticexpense.tracker.domain.IncomeConfirmationStatus;
import com.automaticexpense.tracker.domain.IncomeSource;
import com.automaticexpense.tracker.domain.IncomeSourceType;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.TransactionId;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class IncomeSourceDynamoDbMapperTest {

    @Test
    void mapsConfirmedIncomeSourcesToTheUserScopedIncomeKeyWithoutLosingEvidence() {
        IncomeSource source = IncomeSource.confirmed(
            "income-salary-1", "Acme Payroll", IncomeSourceType.FIXED, Money.of("75000.00", "INR"),
            IncomeCadence.MONTHLY, LocalDate.of(2026, 1, 31), null, new AccountId("account-1"),
            Set.of(new TransactionId("salary-jan"), new TransactionId("salary-feb"))
        );

        Map<String, String> item = DynamoDbItem.fromIncomeSource("principal-42", source);
        IncomeSource reloaded = DynamoDbItem.toIncomeSource(item);

        assertThat(item).containsEntry("PK", "USER#principal-42")
            .containsEntry("SK", "INCOME#income-salary-1")
            .containsEntry("entityType", "INCOME_SOURCE");
        assertThat(reloaded).isEqualTo(source);
        assertThat(reloaded.confirmationStatus()).isEqualTo(IncomeConfirmationStatus.CONFIRMED);
    }
}
