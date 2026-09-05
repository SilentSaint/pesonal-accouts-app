package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.EvaluateFinancialCapabilityUseCase;
import com.automaticexpense.tracker.domain.FinancialSnapshot;
import com.automaticexpense.tracker.domain.IntelligenceResult;
import com.automaticexpense.tracker.domain.SpendingAnalytics;
import com.automaticexpense.tracker.domain.SpendingAnalyticsCalculator;
import com.automaticexpense.tracker.domain.SpendingAnalyticsRequest;

import java.util.Objects;

public final class FinancialCapabilityService implements EvaluateFinancialCapabilityUseCase {
    private final SpendingAnalyticsCalculator spendingAnalytics;

    public FinancialCapabilityService(SpendingAnalyticsCalculator spendingAnalytics) {
        this.spendingAnalytics = Objects.requireNonNull(
            spendingAnalytics, "spendingAnalytics cannot be null"
        );
    }

    @Override
    public IntelligenceResult<SpendingAnalytics> evaluate(
        FinancialSnapshot snapshot,
        SpendingAnalyticsRequest request
    ) {
        return spendingAnalytics.evaluate(snapshot, request);
    }
}
