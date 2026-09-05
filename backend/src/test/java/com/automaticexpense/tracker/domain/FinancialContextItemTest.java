package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDate;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class FinancialContextItemTest {

    @Test
    void exposesOnlyAllowedMinimumBalanceFieldsWhenItIsEffective() {
        FinancialContextItem item = FinancialContextItem.create(
            "context-cash-floor",
            FinancialContextType.PREFERRED_MINIMUM_CASH_BALANCE,
            "Emergency cash floor",
            Map.of("amount", "25000.00", "currency", "INR"),
            Set.of(FinancialContextCapability.CASH_FLOW_FORECAST),
            ContextProvenance.USER_DECLARED,
            LocalDate.of(2026, 8, 1),
            null,
            Instant.parse("2026-08-01T10:00:00Z")
        );

        assertThat(item.isEffectiveAt(Instant.parse("2026-08-29T00:00:00Z"))).isTrue();
        assertThat(item.minimizedFieldsFor(FinancialContextCapability.CASH_FLOW_FORECAST))
            .containsExactlyInAnyOrderEntriesOf(Map.of("amount", "25000.00", "currency", "INR"));
        assertThat(item.minimizedFieldsFor(FinancialContextCapability.FINANCIAL_HEALTH)).isEmpty();
    }

    @Test
    void marksAnActiveItemExpiredAfterItsEffectiveEndDate() {
        FinancialContextItem item = FinancialContextItem.create(
            "context-trip",
            FinancialContextType.MAJOR_PURCHASE_INTENTION,
            "Trip",
            Map.of("plannedAmount", "50000.00", "currency", "INR", "targetDate", "2026-12-01"),
            Set.of(FinancialContextCapability.CASH_FLOW_FORECAST),
            ContextProvenance.USER_DECLARED,
            LocalDate.of(2026, 8, 1),
            LocalDate.of(2026, 8, 15),
            Instant.parse("2026-08-01T10:00:00Z")
        );

        assertThat(item.statusAt(Instant.parse("2026-08-29T00:00:00Z")))
            .isEqualTo(FinancialContextItemStatus.EXPIRED);
    }
}
