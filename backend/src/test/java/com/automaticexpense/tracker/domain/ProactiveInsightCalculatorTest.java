package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class ProactiveInsightCalculatorTest {

    private final ProactiveInsightCalculator calculator = new ProactiveInsightCalculator();

    @Test
    void producesAnExplainableCategoryIncreaseOnlyWhenThreeComparablePeriodsEstablishPersonalHistory() {
        FinancialSnapshot snapshot = new FinancialSnapshot(
            Instant.parse("2026-08-31T12:00:00Z"),
            ZoneId.of("Asia/Kolkata"),
            List.of(
                debit("current-1", "3500.00", "2026-08-12T10:00", "Grocer", "GROCERIES"),
                debit("current-2", "1500.00", "2026-08-18T10:00", "Grocer", "GROCERIES"),
                debit("july", "2000.00", "2026-07-12T10:00", "Grocer", "GROCERIES"),
                debit("june", "1800.00", "2026-06-12T10:00", "Grocer", "GROCERIES"),
                debit("may", "2200.00", "2026-05-12T10:00", "Grocer", "GROCERIES")
            )
        );

        List<ProactiveInsight> insights = calculator.evaluate(snapshot, new ProactiveInsightRequest("INR"));

        assertThat(insights).filteredOn(insight -> insight.type() == ProactiveInsightType.CATEGORY_INCREASE)
            .singleElement()
            .satisfies(insight -> {
                assertThat(insight.classification()).isEqualTo(IntelligenceClassification.DERIVED_INSIGHT);
                assertThat(insight.baselineAmount()).isEqualTo(Money.of("2000.00", "INR"));
                assertThat(insight.currentAmount()).isEqualTo(Money.of("5000.00", "INR"));
                assertThat(insight.baselineLabel()).isEqualTo("three comparable prior months");
                assertThat(insight.matchingTransactions())
                    .extracting(TransactionEvidence::transactionId)
                    .containsExactlyInAnyOrder("current-1", "current-2");
                assertThat(insight.formula()).isEqualTo(ProactiveInsightCalculator.FORMULA);
                assertThat(insight.deduplicationKey()).isEqualTo("CATEGORY_INCREASE:GROCERIES:2026-08");
            });
    }

    @Test
    void suppressesAnOtherwiseLargeChangeWhenTheUsersComparableHistoryIsTooSmall() {
        FinancialSnapshot snapshot = new FinancialSnapshot(
            Instant.parse("2026-08-31T12:00:00Z"),
            ZoneId.of("Asia/Kolkata"),
            List.of(
                debit("current", "10000.00", "2026-08-12T10:00", "Grocer", "GROCERIES"),
                debit("july", "100.00", "2026-07-12T10:00", "Grocer", "GROCERIES")
            )
        );

        List<ProactiveInsight> insights = calculator.evaluate(snapshot, new ProactiveInsightRequest("INR"));

        assertThat(insights).isEmpty();
    }

    @Test
    void identifiesAnUnusualPurchaseAgainstTheUsersOwnCategoryPurchaseHistory() {
        FinancialSnapshot snapshot = new FinancialSnapshot(
            Instant.parse("2026-08-31T12:00:00Z"),
            ZoneId.of("Asia/Kolkata"),
            List.of(
                debit("usual-1", "1000.00", "2026-05-12T10:00", "Device Shop", "ELECTRONICS"),
                debit("usual-2", "1100.00", "2026-06-12T10:00", "Device Shop", "ELECTRONICS"),
                debit("usual-3", "900.00", "2026-07-12T10:00", "Device Shop", "ELECTRONICS"),
                debit("unusual", "5000.00", "2026-08-12T10:00", "Device Shop", "ELECTRONICS")
            )
        );

        List<ProactiveInsight> insights = calculator.evaluate(snapshot, new ProactiveInsightRequest("INR"));

        assertThat(insights).filteredOn(insight -> insight.type() == ProactiveInsightType.UNUSUAL_PURCHASE)
            .singleElement()
            .satisfies(insight -> {
                assertThat(insight.currentAmount()).isEqualTo(Money.of("5000.00", "INR"));
                assertThat(insight.baselineAmount()).isEqualTo(Money.of("1000.00", "INR"));
                assertThat(insight.matchingTransactions())
                    .extracting(TransactionEvidence::transactionId)
                    .containsExactly("unusual");
            });
    }

    @Test
    void comparesAPartialMonthWithEquivalentElapsedDaysInPriorMonths() {
        FinancialSnapshot snapshot = new FinancialSnapshot(
            Instant.parse("2026-08-12T12:00:00Z"),
            ZoneId.of("Asia/Kolkata"),
            List.of(
                debit("current", "1000.00", "2026-08-10T10:00", "Grocer", "GROCERIES"),
                debit("july-early", "400.00", "2026-07-10T10:00", "Grocer", "GROCERIES"),
                debit("july-late", "800.00", "2026-07-25T10:00", "Grocer", "GROCERIES"),
                debit("june-early", "400.00", "2026-06-10T10:00", "Grocer", "GROCERIES"),
                debit("june-late", "800.00", "2026-06-25T10:00", "Grocer", "GROCERIES"),
                debit("may-early", "400.00", "2026-05-10T10:00", "Grocer", "GROCERIES"),
                debit("may-late", "800.00", "2026-05-25T10:00", "Grocer", "GROCERIES")
            )
        );

        List<ProactiveInsight> insights = calculator.evaluate(snapshot, new ProactiveInsightRequest("INR"));

        assertThat(insights).anySatisfy(insight -> {
            assertThat(insight.type()).isEqualTo(ProactiveInsightType.CATEGORY_INCREASE);
            assertThat(insight.baselineAmount()).isEqualTo(Money.of("400.00", "INR"));
        });
    }

    private Transaction debit(String id, String amount, String timestamp, String merchant, String category) {
        return new Transaction(
            new TransactionId(id),
            Money.of(amount, "INR"),
            TransactionType.DEBIT,
            LocalDateTime.parse(timestamp),
            merchant,
            new AccountId("account-1"),
            category,
            IngestionSource.MANUAL,
            ReconciliationStatus.CONFIRMED,
            Money.of(amount, "INR")
        );
    }
}
