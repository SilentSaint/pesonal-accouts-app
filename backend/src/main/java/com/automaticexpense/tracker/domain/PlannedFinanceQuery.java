package com.automaticexpense.tracker.domain;

import java.util.Objects;

public record PlannedFinanceQuery(FinanceQueryPlan plan, boolean usedHostedModel)
    implements FinanceQueryPlanningResult {
    public PlannedFinanceQuery {
        Objects.requireNonNull(plan, "plan cannot be null");
    }
}
