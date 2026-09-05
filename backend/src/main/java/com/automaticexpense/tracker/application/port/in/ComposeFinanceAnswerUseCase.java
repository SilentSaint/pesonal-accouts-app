package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.FinanceAnswer;
import com.automaticexpense.tracker.domain.FinanceQueryPlan;
import com.automaticexpense.tracker.domain.IntelligenceResult;
import com.automaticexpense.tracker.domain.SpendingAnalytics;

public interface ComposeFinanceAnswerUseCase {
    FinanceAnswer compose(FinanceQueryPlan plan, IntelligenceResult<SpendingAnalytics> result);
}
