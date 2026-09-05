package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.EvaluateFinancialCapabilityUseCase;
import com.automaticexpense.tracker.application.port.in.LoadFinancialSnapshotUseCase;
import com.automaticexpense.tracker.application.port.out.FinancialSnapshotRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.FinancialSnapshot;
import com.automaticexpense.tracker.domain.FinancialSnapshotRequest;
import com.automaticexpense.tracker.domain.FormulaReference;
import com.automaticexpense.tracker.domain.IntelligenceResult;
import com.automaticexpense.tracker.domain.SpendingAnalytics;
import com.automaticexpense.tracker.domain.SpendingAnalyticsCalculator;
import com.automaticexpense.tracker.domain.SpendingAnalyticsRequest;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class FinancialIntelligenceUseCaseTest {

    @Test
    void loadsAnAsOfSnapshotBeforeEvaluatingAnExplainableCapability() {
        FinancialSnapshot snapshot = new FinancialSnapshot(
            Instant.parse("2026-08-31T18:30:00Z"),
            ZoneId.of("Asia/Kolkata"),
            List.of()
        );
        FinancialSnapshotRepository repository = request -> snapshot;
        LoadFinancialSnapshotUseCase load = new FinancialSnapshotService(repository);
        EvaluateFinancialCapabilityUseCase evaluate =
            new FinancialCapabilityService(new SpendingAnalyticsCalculator());
        FinancialSnapshotRequest snapshotRequest = new FinancialSnapshotRequest(
            snapshot.asOf(), snapshot.timezone(), Set.of(new AccountId("account-1")), "INR"
        );

        IntelligenceResult<FinancialSnapshot> loaded = load.load(snapshotRequest);
        IntelligenceResult<SpendingAnalytics> result = evaluate.evaluate(
            loaded.value(),
            new SpendingAnalyticsRequest(
                new com.automaticexpense.tracker.domain.DateRange(
                    java.time.LocalDate.of(2026, 8, 1), java.time.LocalDate.of(2026, 8, 31)
                ),
                "INR",
                Set.of(),
                null,
                null,
                1
            )
        );

        assertThat(loaded.value()).isSameAs(snapshot);
        assertThat(loaded.formula()).isEqualTo(new FormulaReference("financial-snapshot", "1.0.0"));
        assertThat(loaded.confidence()).isEqualByComparingTo("1.0");
        assertThat(loaded.evidence().sourceCount()).isZero();
        assertThat(result.formula()).isEqualTo(SpendingAnalyticsCalculator.FORMULA);
    }
}
