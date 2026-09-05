package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.FinancialGoal;
import com.automaticexpense.tracker.domain.FinancialGoalProjection;
import com.automaticexpense.tracker.domain.GoalCashFlowImpact;
import com.automaticexpense.tracker.domain.GoalContribution;
import com.automaticexpense.tracker.domain.IntelligenceResult;

import java.time.LocalDate;
import java.util.List;

public interface ManageFinancialGoalUseCase {
    FinancialGoal create(FinancialGoalDraft draft);

    FinancialGoal update(String id, FinancialGoalDraft draft);

    FinancialGoal pause(String id);

    FinancialGoal resume(String id);

    FinancialGoal complete(String id);

    FinancialGoal recordContribution(String id, GoalContribution contribution);

    void delete(String id);

    List<FinancialGoal> list();

    IntelligenceResult<FinancialGoalProjection> project(
        String id, LocalDate asOf, GoalCashFlowImpact cashFlowImpact
    );
}
