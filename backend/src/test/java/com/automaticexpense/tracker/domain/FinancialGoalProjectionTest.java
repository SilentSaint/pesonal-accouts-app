package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class FinancialGoalProjectionTest {

    @Test
    void projectsRequiredPaceCompletionAndMinimumBalanceRiskFromExplicitAllocations() {
        FinancialGoal goal = FinancialGoal.active(
            "car", "Car", Money.of("1200.00", "INR"), LocalDate.of(2026, 6, 30),
            List.of(new GoalAllocation("car-savings", Money.of("200.00", "INR"), "savings-account")),
            GoalPriority.HIGH, GoalContributionRule.none()
        ).recordContribution(new GoalContribution(
            "car-jan", Money.of("100.00", "INR"), LocalDate.of(2026, 1, 31), "transaction-jan"
        )).recordContribution(new GoalContribution(
            "car-feb", Money.of("100.00", "INR"), LocalDate.of(2026, 2, 28), "transaction-feb"
        ));

        FinancialGoalProjection projection = goal.project(
            LocalDate.of(2026, 3, 1),
            new GoalCashFlowImpact(
                Money.of("1000.00", "INR"), Money.of("850.00", "INR"), LocalDate.of(2026, 3, 1)
            )
        );

        assertThat(projection).isEqualTo(new FinancialGoalProjection(
            Money.of("800.00", "INR"), 4, Money.of("200.00", "INR"),
            Money.of("66.67", "INR"), LocalDate.of(2027, 2, 28),
            Money.of("-133.33", "INR"), true, GoalProjectionStatus.AT_RISK,
            List.of("transaction-jan", "transaction-feb")
        ));
    }
}
