package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.domain.DateRange;
import com.automaticexpense.tracker.domain.EvidenceMetadata;
import com.automaticexpense.tracker.domain.FinanceAnswer;
import com.automaticexpense.tracker.domain.FinanceQueryCapability;
import com.automaticexpense.tracker.domain.FinanceQueryFilters;
import com.automaticexpense.tracker.domain.FinanceQueryPlan;
import com.automaticexpense.tracker.domain.FormulaReference;
import com.automaticexpense.tracker.domain.IntelligenceClassification;
import com.automaticexpense.tracker.domain.IntelligenceResult;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.PeriodComparison;
import com.automaticexpense.tracker.domain.PeriodSpending;
import com.automaticexpense.tracker.domain.SpendingAnalytics;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class FinanceAnswerComposerUseCaseTest {

    @Test
    void composesAComparisonOnlyFromTheDeterministicResultEnvelope() {
        DateRange currentRange = new DateRange(LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31));
        PeriodSpending current = new PeriodSpending(currentRange, Money.of("300.00", "INR"), 2);
        PeriodSpending baseline = new PeriodSpending(
            new DateRange(LocalDate.of(2026, 7, 1), LocalDate.of(2026, 7, 31)),
            Money.of("200.00", "INR"), 1
        );
        SpendingAnalytics analytics = new SpendingAnalytics(
            current, baseline, baseline,
            new PeriodComparison(baseline, Money.of("100.00", "INR"), new BigDecimal("50.00")),
            new PeriodComparison(baseline, Money.of("100.00", "INR"), new BigDecimal("50.00")),
            Money.of("250.00", "INR"), 2, Money.of("150.00", "INR"),
            List.of(), List.of(), List.of(), List.of(), current, baseline
        );
        IntelligenceResult<SpendingAnalytics> result = new IntelligenceResult<>(
            IntelligenceClassification.FACT,
            analytics,
            Instant.parse("2026-08-31T18:30:00Z"),
            Instant.parse("2026-08-31T18:30:00Z"),
            BigDecimal.ONE,
            new FormulaReference("spending-analytics", "1.0.0"),
            new EvidenceMetadata(2, null),
            List.of("Only canonical debit records are included."),
            List.of()
        );

        FinanceAnswer answer = new FinanceAnswerComposerService().compose(
            new FinanceQueryPlan(
                FinanceQueryCapability.PERIOD_COMPARISON,
                new FinanceQueryFilters(currentRange, "INR", Set.of(), null, null)
            ),
            result
        );

        assertThat(answer.observation()).isEqualTo(
            "Personal spending is INR 300.00 for the selected period versus INR 200.00"
                + " in the comparison period, a 50.00% change."
        );
        assertThat(answer.assumptions()).containsExactly("Only canonical debit records are included.");
        assertThat(answer.formula()).isEqualTo(new FormulaReference("spending-analytics", "1.0.0"));
    }
}
