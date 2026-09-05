package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.ContextProvenance;
import com.automaticexpense.tracker.domain.FinancialContextCapability;
import com.automaticexpense.tracker.domain.FinancialContextItem;
import com.automaticexpense.tracker.domain.FinancialContextType;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDate;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class FinancialContextDynamoDbMapperTest {

    @Test
    void mapsUserDeclaredContextToTheSingleTableContextKeyAndBack() {
        FinancialContextItem context = FinancialContextItem.create(
            "ctx-floor-001",
            FinancialContextType.PREFERRED_MINIMUM_CASH_BALANCE,
            "Emergency floor",
            Map.of("amount", "25000.00", "currency", "INR"),
            Set.of(FinancialContextCapability.CASH_FLOW_FORECAST),
            ContextProvenance.USER_DECLARED,
            LocalDate.of(2026, 8, 1),
            null,
            Instant.parse("2026-08-01T10:00:00Z")
        );

        Map<String, String> persisted = DynamoDbItem.fromFinancialContextItem("verified-subject", context);

        assertThat(persisted).containsEntry("PK", "USER#verified-subject")
            .containsEntry("SK", "CONTEXT#ctx-floor-001")
            .containsEntry("entityType", "FINANCIAL_CONTEXT");
        assertThat(DynamoDbItem.toFinancialContextItem(persisted)).isEqualTo(context);
    }
}
