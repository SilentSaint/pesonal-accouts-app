package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.FinanceQuery;
import com.automaticexpense.tracker.domain.FinanceQueryAliases;
import com.automaticexpense.tracker.domain.FinanceQueryPlanningResult;

public interface PlanFinanceQueryUseCase {
    FinanceQueryPlanningResult plan(FinanceQuery query, FinanceQueryAliases aliases);
}
