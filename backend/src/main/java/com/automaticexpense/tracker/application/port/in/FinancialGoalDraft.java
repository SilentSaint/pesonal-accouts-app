package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.GoalAllocation;
import com.automaticexpense.tracker.domain.GoalContributionRule;
import com.automaticexpense.tracker.domain.GoalPriority;
import com.automaticexpense.tracker.domain.Money;

import java.time.LocalDate;
import java.util.List;

public record FinancialGoalDraft(
    String name,
    Money targetAmount,
    LocalDate targetDate,
    List<GoalAllocation> allocations,
    GoalPriority priority,
    GoalContributionRule contributionRule
) { }
