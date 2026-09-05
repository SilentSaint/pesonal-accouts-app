package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class SpendingAnalyticsCalculatorTest {

    private final SpendingAnalyticsCalculator calculator = new SpendingAnalyticsCalculator();

    @Test
    void evaluatesComparablePeriodsAndEvidenceFromCanonicalPersonalSpending() {
        FinancialSnapshot snapshot = new FinancialSnapshot(
            Instant.parse("2026-08-29T12:00:00Z"),
            ZoneId.of("Asia/Kolkata"),
            List.of(
                debit("aug-groceries", "100.00", "2026-08-02T10:00", "Grocer", "GROCERIES",
                    ReconciliationStatus.CONFIRMED, null),
                debit("aug-dining", "200.00", "2026-08-10T10:00", "Bistro", "DINING",
                    ReconciliationStatus.CONFIRMED, null),
                debit("aug-split", "300.00", "2026-08-20T10:00", "Trip", "TRAVEL",
                    ReconciliationStatus.CONFIRMED, "100.00"),
                debit("transfer", "400.00", "2026-08-21T10:00", "Own account", "TRANSFER",
                    ReconciliationStatus.CONFIRMED, null, "•••• 1234"),
                debit("unreviewed", "50.00", "2026-08-22T10:00", "Pending", "DINING",
                    ReconciliationStatus.NEEDS_REVIEW, null),
                debit("july", "120.00", "2026-07-10T10:00", "Grocer", "GROCERIES",
                    ReconciliationStatus.CONFIRMED, null),
                debit("june", "60.00", "2026-06-10T10:00", "Grocer", "GROCERIES",
                    ReconciliationStatus.CONFIRMED, null),
                debit("last-year", "80.00", "2025-08-10T10:00", "Bistro", "DINING",
                    ReconciliationStatus.CONFIRMED, null)
            )
        );

        IntelligenceResult<SpendingAnalytics> result = calculator.evaluate(
            snapshot,
            new SpendingAnalyticsRequest(
                new DateRange(LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31)),
                "INR",
                Set.of(),
                null,
                null,
                3
            )
        );

        assertThat(result.classification()).isEqualTo(IntelligenceClassification.FACT);
        assertThat(result.formula()).isEqualTo(new FormulaReference("spending-analytics", "1.0.0"));
        assertThat(result.confidence()).isEqualByComparingTo("1.0");
        assertThat(result.freshnessAsOf()).isEqualTo(Instant.parse("2026-08-29T12:00:00Z"));
        assertThat(result.value().currentPeriod().total()).isEqualTo(Money.of("400.00", "INR"));
        assertThat(result.value().previousPeriod().total()).isEqualTo(Money.of("120.00", "INR"));
        assertThat(result.value().yearOverYearPeriod().total()).isEqualTo(Money.of("80.00", "INR"));
        assertThat(result.value().monthOverMonth().percentageChange()).isEqualByComparingTo("233.33");
        assertThat(result.value().yearOverYear().percentageChange()).isEqualByComparingTo("400.00");
        assertThat(result.value().rollingAverage()).isEqualTo(Money.of("193.33", "INR"));
        assertThat(result.value().transactionFrequency()).isEqualTo(3);
        assertThat(result.value().averageTransactionValue()).isEqualTo(Money.of("133.33", "INR"));
        assertThat(result.value().categoryBreakdown())
            .extracting(SpendingBreakdown::key, SpendingBreakdown::total)
            .containsExactly(
                org.assertj.core.groups.Tuple.tuple("DINING", Money.of("200.00", "INR")),
                org.assertj.core.groups.Tuple.tuple("GROCERIES", Money.of("100.00", "INR")),
                org.assertj.core.groups.Tuple.tuple("TRAVEL", Money.of("100.00", "INR"))
            );
        assertThat(result.value().largestPurchases())
            .extracting(TransactionEvidence::transactionId)
            .containsExactly("aug-dining", "aug-groceries", "aug-split");
        assertThat(result.value().highestPeriod().period())
            .isEqualTo(new DateRange(LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31)));
        assertThat(result.warnings())
            .contains(IntelligenceWarning.INCOMPLETE_PERIOD, IntelligenceWarning.EXCLUDED_NON_CANONICAL_RECORDS);
        assertThat(result.evidence().sourceCount()).isEqualTo(3);
    }

    @Test
    void warnsInsteadOfInventingAPercentageWhenComparisonHistoryIsMissing() {
        FinancialSnapshot snapshot = new FinancialSnapshot(
            Instant.parse("2026-08-31T18:30:00Z"),
            ZoneId.of("Asia/Kolkata"),
            List.of(debit("only-current", "75.00", "2026-08-10T10:00", "Grocer",
                "GROCERIES", ReconciliationStatus.CONFIRMED, null))
        );

        IntelligenceResult<SpendingAnalytics> result = calculator.evaluate(
            snapshot,
            new SpendingAnalyticsRequest(
                new DateRange(LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31)),
                "INR",
                Set.of(),
                null,
                null,
                2
            )
        );

        assertThat(result.value().monthOverMonth().percentageChange()).isNull();
        assertThat(result.value().yearOverYear().percentageChange()).isNull();
        assertThat(result.warnings()).contains(
            IntelligenceWarning.INSUFFICIENT_HISTORY,
            IntelligenceWarning.MISSING_COMPARISON_BASELINE
        );
    }

    @Test
    void assignsStoredUtcTransactionsToTheReportingTimezonePeriod() {
        FinancialSnapshot snapshot = new FinancialSnapshot(
            Instant.parse("2026-08-01T00:00:00Z"),
            ZoneId.of("Asia/Kolkata"),
            List.of(debit("boundary-purchase", "90.00", "2026-07-31T20:00", "Night market",
                "DINING", ReconciliationStatus.CONFIRMED, null))
        );

        IntelligenceResult<SpendingAnalytics> result = calculator.evaluate(
            snapshot,
            new SpendingAnalyticsRequest(
                new DateRange(LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31)),
                "INR", Set.of(), null, null, 1
            )
        );

        assertThat(result.value().currentPeriod().total()).isEqualTo(Money.of("90.00", "INR"));
        assertThat(result.value().currentPeriod().transactionCount()).isEqualTo(1);
    }

    private Transaction debit(
        String id,
        String amount,
        String timestamp,
        String merchant,
        String category,
        ReconciliationStatus status,
        String netPersonalExpense
    ) {
        return debit(id, amount, timestamp, merchant, category, status, netPersonalExpense, null);
    }

    private Transaction debit(
        String id,
        String amount,
        String timestamp,
        String merchant,
        String category,
        ReconciliationStatus status,
        String netPersonalExpense,
        String transferCounterpartMask
    ) {
        return new Transaction(
            new TransactionId(id),
            Money.of(amount, "INR"),
            TransactionType.DEBIT,
            LocalDateTime.parse(timestamp),
            merchant,
            new AccountId("account-1"),
            category,
            null,
            IngestionSource.MANUAL,
            status,
            netPersonalExpense == null ? null : Money.of(netPersonalExpense, "INR"),
            null,
            null,
            null,
            transferCounterpartMask
        );
    }
}
