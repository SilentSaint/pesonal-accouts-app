package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.FinancialGoalDraft;
import com.automaticexpense.tracker.application.port.in.ManageFinancialGoalUseCase;
import com.automaticexpense.tracker.application.port.out.FinancialGoalRepository;
import com.automaticexpense.tracker.domain.EvidenceMetadata;
import com.automaticexpense.tracker.domain.FinancialGoal;
import com.automaticexpense.tracker.domain.FinancialGoalProjection;
import com.automaticexpense.tracker.domain.FormulaReference;
import com.automaticexpense.tracker.domain.GoalAllocation;
import com.automaticexpense.tracker.domain.GoalCashFlowImpact;
import com.automaticexpense.tracker.domain.GoalContribution;
import com.automaticexpense.tracker.domain.GoalProjectionStatus;
import com.automaticexpense.tracker.domain.IntelligenceClassification;
import com.automaticexpense.tracker.domain.IntelligenceResult;
import com.automaticexpense.tracker.domain.IntelligenceWarning;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public final class FinancialGoalService implements ManageFinancialGoalUseCase {
    private static final FormulaReference FORMULA = new FormulaReference("financial-goal-projection", "1.0.0");
    private final FinancialGoalRepository goals;

    public FinancialGoalService(FinancialGoalRepository goals) {
        this.goals = Objects.requireNonNull(goals, "goals cannot be null");
    }

    @Override
    public FinancialGoal create(FinancialGoalDraft draft) {
        Objects.requireNonNull(draft, "draft cannot be null");
        validateUnclaimedAllocations(draft.allocations(), null);
        FinancialGoal goal = FinancialGoal.active(
            UUID.randomUUID().toString(), draft.name(), draft.targetAmount(), draft.targetDate(),
            draft.allocations(), draft.priority(), draft.contributionRule()
        );
        goals.save(goal);
        return goal;
    }

    @Override
    public FinancialGoal update(String id, FinancialGoalDraft draft) {
        Objects.requireNonNull(draft, "draft cannot be null");
        FinancialGoal existing = goal(id);
        validateUnclaimedAllocations(draft.allocations(), existing.id());
        FinancialGoal updated = existing.update(
            draft.name(), draft.targetAmount(), draft.targetDate(), draft.allocations(),
            draft.priority(), draft.contributionRule()
        );
        goals.save(updated);
        return updated;
    }

    @Override
    public FinancialGoal pause(String id) {
        return save(goal(id).pause());
    }

    @Override
    public FinancialGoal resume(String id) {
        return save(goal(id).resume());
    }

    @Override
    public FinancialGoal complete(String id) {
        return save(goal(id).complete());
    }

    @Override
    public FinancialGoal recordContribution(String id, GoalContribution contribution) {
        return save(goal(id).recordContribution(contribution));
    }

    @Override
    public void delete(String id) {
        goal(id);
        goals.deleteById(id);
    }

    @Override
    public List<FinancialGoal> list() {
        return goals.findAll();
    }

    @Override
    public IntelligenceResult<FinancialGoalProjection> project(
        String id, LocalDate asOf, GoalCashFlowImpact cashFlowImpact
    ) {
        FinancialGoalProjection projection = goal(id).project(asOf, cashFlowImpact);
        List<IntelligenceWarning> warnings = new ArrayList<>();
        if (projection.status() == GoalProjectionStatus.INSUFFICIENT_DATA) {
            warnings.add(IntelligenceWarning.INSUFFICIENT_HISTORY);
        }
        return new IntelligenceResult<>(
            IntelligenceClassification.PREDICTION,
            projection,
            asOf.atStartOfDay().toInstant(ZoneOffset.UTC),
            asOf.atStartOfDay().toInstant(ZoneOffset.UTC),
            confidence(projection, cashFlowImpact),
            FORMULA,
            new EvidenceMetadata(projection.contributionEvidenceReferences().size(), null),
            assumptions(projection, cashFlowImpact),
            warnings
        );
    }

    private void validateUnclaimedAllocations(List<GoalAllocation> allocations, String excludedGoalId) {
        Objects.requireNonNull(allocations, "allocations cannot be null");
        for (GoalAllocation allocation : allocations) {
            goals.findAll().stream()
                .filter(goal -> !goal.id().equals(excludedGoalId))
                .flatMap(goal -> goal.allocations().stream())
                .filter(existing -> existing.reference().equals(allocation.reference()))
                .findFirst()
                .ifPresent(existing -> {
                    throw new IllegalArgumentException(
                        "Savings allocation is already assigned to another goal: " + allocation.reference()
                    );
                });
        }
    }

    private FinancialGoal goal(String id) {
        return goals.findById(id)
            .orElseThrow(() -> new IllegalArgumentException("Financial goal not found: " + id));
    }

    private FinancialGoal save(FinancialGoal goal) {
        goals.save(goal);
        return goal;
    }

    private BigDecimal confidence(FinancialGoalProjection projection, GoalCashFlowImpact cashFlowImpact) {
        if (projection.status() == GoalProjectionStatus.INSUFFICIENT_DATA) return new BigDecimal("0.25");
        BigDecimal confidence = projection.contributionEvidenceReferences().isEmpty()
            ? new BigDecimal("0.50") : new BigDecimal("0.70");
        if (cashFlowImpact != null) confidence = confidence.add(new BigDecimal("0.10"));
        return confidence;
    }

    private List<String> assumptions(FinancialGoalProjection projection, GoalCashFlowImpact cashFlowImpact) {
        List<String> assumptions = new ArrayList<>();
        assumptions.add("Only explicitly assigned savings allocations and recorded goal contributions count toward progress.");
        assumptions.add("Observed contribution pace is the net recorded contribution amount divided by calendar months since first evidence.");
        if (projection.observedMonthlyContribution().amount().signum() <= 0) {
            assumptions.add("The configured contribution rule is used only when observed net progress is not positive.");
        }
        if (cashFlowImpact == null) {
            assumptions.add("No authoritative cash-flow forecast was available to assess the preferred minimum balance.");
        }
        return List.copyOf(assumptions);
    }
}
