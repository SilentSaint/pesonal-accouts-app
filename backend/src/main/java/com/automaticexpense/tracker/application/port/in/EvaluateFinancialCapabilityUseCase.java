package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.FinancialSnapshot;
import com.automaticexpense.tracker.domain.IntelligenceResult;
import com.automaticexpense.tracker.domain.SpendingAnalytics;
import com.automaticexpense.tracker.domain.SpendingAnalyticsRequest;

public interface EvaluateFinancialCapabilityUseCase {
    IntelligenceResult<SpendingAnalytics> evaluate(
        FinancialSnapshot snapshot,
        SpendingAnalyticsRequest request
    );
}
