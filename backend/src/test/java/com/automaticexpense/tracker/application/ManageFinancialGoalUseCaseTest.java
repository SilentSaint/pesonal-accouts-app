package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.FinancialGoalDraft;
import com.automaticexpense.tracker.application.port.in.ManageFinancialGoalUseCase;
import com.automaticexpense.tracker.application.port.out.FinancialGoalRepository;
import com.automaticexpense.tracker.domain.FinancialGoal;
import com.automaticexpense.tracker.domain.GoalAllocation;
import com.automaticexpense.tracker.domain.GoalContribution;
import com.automaticexpense.tracker.domain.GoalContributionRule;
import com.automaticexpense.tracker.domain.GoalPriority;
import com.automaticexpense.tracker.domain.IntelligenceClassification;
import com.automaticexpense.tracker.domain.Money;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ManageFinancialGoalUseCaseTest {

    @Test
    void letsAUserEditPauseResumeCompleteAndDeleteAGoal() {
        ManageFinancialGoalUseCase goals = new FinancialGoalService(new InMemoryGoals());
        FinancialGoal created = goals.create(new FinancialGoalDraft(
            "Holiday", Money.of("1000.00", "INR"), LocalDate.of(2026, 12, 31),
            List.of(), GoalPriority.MEDIUM, GoalContributionRule.none()
        ));
        FinancialGoal updated = goals.update(created.id(), new FinancialGoalDraft(
            "Holiday in Japan", Money.of("1200.00", "INR"), LocalDate.of(2027, 1, 31),
            List.of(new GoalAllocation("holiday-fund", Money.of("100.00", "INR"), "savings")),
            GoalPriority.HIGH, GoalContributionRule.none()
        ));
        goals.pause(updated.id());
        goals.resume(updated.id());
        goals.recordContribution(updated.id(), new GoalContribution(
            "holiday-march", Money.of("50.00", "INR"), LocalDate.of(2026, 3, 1), "transaction-march"
        ));
        FinancialGoal completed = goals.complete(updated.id());
        goals.delete(updated.id());

        assertThat(completed.lifecycle().name()).isEqualTo("COMPLETED");
        assertThat(goals.list()).isEmpty();
    }

    @Test
    void preventsAnExplicitSavingsAllocationFromBeingClaimedByMoreThanOneGoal() {
        ManageFinancialGoalUseCase goals = new FinancialGoalService(new InMemoryGoals());
        FinancialGoal first = goals.create(new FinancialGoalDraft(
            "Home deposit", Money.of("100000.00", "INR"), LocalDate.of(2027, 12, 31),
            List.of(new GoalAllocation("savings-reserve", Money.of("25000.00", "INR"), "savings")),
            GoalPriority.HIGH, GoalContributionRule.none()
        ));

        assertThatThrownBy(() -> goals.create(new FinancialGoalDraft(
            "Emergency fund", Money.of("300000.00", "INR"), LocalDate.of(2028, 12, 31),
            List.of(new GoalAllocation("savings-reserve", Money.of("25000.00", "INR"), "savings")),
            GoalPriority.HIGH, GoalContributionRule.none()
        ))).isInstanceOf(IllegalArgumentException.class)
            .hasMessageContaining("savings-reserve");
        assertThat(goals.project(first.id(), LocalDate.of(2026, 3, 1), null).classification())
            .isEqualTo(IntelligenceClassification.PREDICTION);
    }

    private static final class InMemoryGoals implements FinancialGoalRepository {
        private final List<FinancialGoal> goals = new ArrayList<>();

        @Override
        public void save(FinancialGoal goal) {
            goals.removeIf(existing -> existing.id().equals(goal.id()));
            goals.add(goal);
        }

        @Override
        public Optional<FinancialGoal> findById(String id) {
            return goals.stream().filter(goal -> goal.id().equals(id)).findFirst();
        }

        @Override
        public List<FinancialGoal> findAll() {
            return List.copyOf(goals);
        }

        @Override
        public void deleteById(String id) {
            goals.removeIf(goal -> goal.id().equals(id));
        }
    }
}
