package com.automaticexpense.tracker.domain;

public sealed interface FinanceQueryPlanningResult permits PlannedFinanceQuery, FinanceQueryClarification {
}
