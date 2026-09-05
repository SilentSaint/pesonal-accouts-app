package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class FinancialGoalLifecycleTest {

    @Test
    void reportsInsufficientDataForZeroOrNegativeObservedProgressWithoutAContributionRule() {
        FinancialGoal goal = FinancialGoal.active(
            "holiday", "Holiday", Money.of("1000.00", "INR"), LocalDate.of(2026, 6, 30),
            List.of(new GoalAllocation("holiday-savings", Money.of("100.00", "INR"), null)),
            GoalPriority.MEDIUM, GoalContributionRule.none()
        ).recordContribution(new GoalContribution(
            "withdrawal", Money.of("-25.00", "INR"), LocalDate.of(2026, 2, 15), "withdrawal-transaction"
        ));

        FinancialGoalProjection projection = goal.project(LocalDate.of(2026, 3, 1), null);

        assertThat(projection.status()).isEqualTo(GoalProjectionStatus.INSUFFICIENT_DATA);
    }

    @Test
    void keepsACompletedGoalCompletedWhenItsProjectionIsRead() {
        FinancialGoal goal = FinancialGoal.active(
            "emergency", "Emergency fund", Money.of("500.00", "INR"), LocalDate.of(2026, 6, 30),
            List.of(new GoalAllocation("emergency-savings", Money.of("500.00", "INR"), "savings")),
            GoalPriority.HIGH, GoalContributionRule.none()
        ).complete();

        assertThat(goal.project(LocalDate.of(2026, 3, 1), null).status())
            .isEqualTo(GoalProjectionStatus.COMPLETED);
    }
}
