package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;

/**
 * A user-owned savings target. Progress only includes savings allocations and contribution records
 * deliberately assigned to this goal.
 */
public record FinancialGoal(
    String id,
    String name,
    Money targetAmount,
    LocalDate targetDate,
    List<GoalAllocation> allocations,
    GoalPriority priority,
    GoalContributionRule contributionRule,
    FinancialGoalLifecycle lifecycle,
    List<GoalContribution> contributions
) {
    public FinancialGoal {
        if (id == null || id.isBlank()) throw new IllegalArgumentException("id cannot be blank");
        if (name == null || name.isBlank()) throw new IllegalArgumentException("name cannot be blank");
        Objects.requireNonNull(targetAmount, "targetAmount cannot be null");
        if (targetAmount.amount().signum() <= 0) throw new IllegalArgumentException("targetAmount must be positive");
        Objects.requireNonNull(targetDate, "targetDate cannot be null");
        allocations = List.copyOf(Objects.requireNonNull(allocations, "allocations cannot be null"));
        if (allocations.size() > 12) {
            throw new IllegalArgumentException("a goal may have at most 12 allocations");
        }
        Set<String> references = new LinkedHashSet<>();
        for (GoalAllocation allocation : allocations) {
            targetAmount.compareTo(allocation.amount());
            if (!references.add(allocation.reference())) {
                throw new IllegalArgumentException("allocation references must be unique");
            }
        }
        Objects.requireNonNull(priority, "priority cannot be null");
        contributionRule = contributionRule == null ? GoalContributionRule.none() : contributionRule;
        if (contributionRule.isConfigured()) targetAmount.compareTo(contributionRule.amount());
        Objects.requireNonNull(lifecycle, "lifecycle cannot be null");
        contributions = List.copyOf(Objects.requireNonNull(contributions, "contributions cannot be null"));
        Set<String> contributionIds = new LinkedHashSet<>();
        for (GoalContribution contribution : contributions) {
            targetAmount.compareTo(contribution.amount());
            if (!contributionIds.add(contribution.id())) {
                throw new IllegalArgumentException("contribution ids must be unique");
            }
        }
        if (totalSavings(targetAmount.currency(), allocations, contributions).amount().signum() < 0) {
            throw new IllegalArgumentException("goal allocations cannot be negative");
        }
    }

    public static FinancialGoal active(
        String id, String name, Money targetAmount, LocalDate targetDate, List<GoalAllocation> allocations,
        GoalPriority priority, GoalContributionRule contributionRule
    ) {
        return new FinancialGoal(
            id, name, targetAmount, targetDate, allocations, priority, contributionRule,
            FinancialGoalLifecycle.ACTIVE, List.of()
        );
    }

    public Money allocatedSavings() {
        return totalSavings(targetAmount.currency(), allocations, contributions);
    }

    public FinancialGoal recordContribution(GoalContribution contribution) {
        Objects.requireNonNull(contribution, "contribution cannot be null");
        if (lifecycle != FinancialGoalLifecycle.ACTIVE) {
            throw new IllegalStateException("only active goals can receive contributions");
        }
        if (contributions.stream().anyMatch(existing -> existing.id().equals(contribution.id()))) {
            throw new IllegalArgumentException("contribution id already exists");
        }
        List<GoalContribution> updated = new ArrayList<>(contributions);
        updated.add(contribution);
        return new FinancialGoal(
            id, name, targetAmount, targetDate, allocations, priority, contributionRule, lifecycle, updated
        );
    }

    public FinancialGoal pause() {
        return transition(FinancialGoalLifecycle.PAUSED);
    }

    public FinancialGoal resume() {
        return transition(FinancialGoalLifecycle.ACTIVE);
    }

    public FinancialGoal complete() {
        return transition(FinancialGoalLifecycle.COMPLETED);
    }

    public FinancialGoal update(
        String newName, Money newTargetAmount, LocalDate newTargetDate, List<GoalAllocation> newAllocations,
        GoalPriority newPriority, GoalContributionRule newContributionRule
    ) {
        if (lifecycle == FinancialGoalLifecycle.COMPLETED) {
            throw new IllegalStateException("completed goals cannot be edited");
        }
        return new FinancialGoal(
            id, newName, newTargetAmount, newTargetDate, newAllocations, newPriority, newContributionRule,
            lifecycle, contributions
        );
    }

    public FinancialGoalProjection project(LocalDate asOf, GoalCashFlowImpact cashFlowImpact) {
        Objects.requireNonNull(asOf, "asOf cannot be null");
        if (cashFlowImpact != null) {
            targetAmount.compareTo(cashFlowImpact.forecastMinimumBalance());
            if (!cashFlowImpact.asOf().equals(asOf)) {
                throw new IllegalArgumentException("cash-flow impact must have the same asOf date");
            }
        }
        Money saved = allocatedSavings();
        Money remaining = Money.of(targetAmount.amount().subtract(saved.amount()).max(BigDecimal.ZERO),
            targetAmount.currency());
        int remainingMonths = monthsThrough(asOf, targetDate);
        Money required = remainingMonths == 0
            ? remaining
            : Money.of(remaining.amount().divide(BigDecimal.valueOf(remainingMonths), 2, RoundingMode.HALF_UP),
                targetAmount.currency());
        List<GoalContribution> observed = contributions.stream()
            .filter(contribution -> !contribution.contributedOn().isAfter(asOf))
            .sorted(Comparator.comparing(GoalContribution::contributedOn).thenComparing(GoalContribution::id))
            .toList();
        Money observedRate = observedMonthlyRate(observed, asOf);
        Money effectiveRate = observedRate.amount().signum() > 0
            ? observedRate
            : contributionRule.isConfigured() ? contributionRule.monthlyAmount() : Money.zero(targetAmount.currency());
        LocalDate projectedDate = projectedCompletionDate(remaining, effectiveRate, asOf);
        boolean breachesMinimum = required.amount().signum() > 0 && cashFlowImpact != null
            && cashFlowImpact.forecastMinimumBalance().subtract(required)
                .compareTo(cashFlowImpact.preferredMinimumBalance()) < 0;
        GoalProjectionStatus status = status(remaining, remainingMonths, projectedDate, effectiveRate, breachesMinimum);
        List<String> evidence = observed.stream()
            .map(GoalContribution::evidenceReference)
            .filter(Objects::nonNull)
            .distinct()
            .toList();
        return new FinancialGoalProjection(
            remaining, remainingMonths, required, observedRate, projectedDate,
            observedRate.subtract(required), breachesMinimum, status, evidence
        );
    }

    private FinancialGoal transition(FinancialGoalLifecycle next) {
        if (lifecycle == FinancialGoalLifecycle.COMPLETED && next != FinancialGoalLifecycle.COMPLETED) {
            throw new IllegalStateException("completed goals cannot be reopened");
        }

        return new FinancialGoal(
            id, name, targetAmount, targetDate, allocations, priority, contributionRule, next, contributions
        );
    }

    private static Money totalSavings(
        String currency, List<GoalAllocation> allocations, List<GoalContribution> contributions
    ) {
        Money total = Money.zero(currency);
        for (GoalAllocation allocation : allocations) total = total.add(allocation.amount());
        for (GoalContribution contribution : contributions) total = total.add(contribution.amount());
        return total;
    }

    private int monthsThrough(LocalDate asOf, LocalDate through) {
        if (through.isBefore(asOf)) return 0;
        return (int) java.time.temporal.ChronoUnit.MONTHS.between(
            YearMonth.from(asOf), YearMonth.from(through)
        ) + 1;
    }

    private Money observedMonthlyRate(List<GoalContribution> observed, LocalDate asOf) {
        if (observed.isEmpty()) return Money.zero(targetAmount.currency());
        Money total = Money.zero(targetAmount.currency());
        for (GoalContribution contribution : observed) total = total.add(contribution.amount());
        int elapsedMonths = (int) java.time.temporal.ChronoUnit.MONTHS.between(
            YearMonth.from(observed.getFirst().contributedOn()), YearMonth.from(asOf)
        ) + 1;
        return Money.of(total.amount().divide(BigDecimal.valueOf(elapsedMonths), 2, RoundingMode.HALF_UP),
            targetAmount.currency());
    }

    private LocalDate projectedCompletionDate(Money remaining, Money rate, LocalDate asOf) {
        if (remaining.isZero()) return asOf;
        if (rate.amount().signum() <= 0) return null;
        int contributionMonths = remaining.amount().divide(rate.amount(), 0, RoundingMode.CEILING).intValueExact();
        return YearMonth.from(asOf).plusMonths(contributionMonths - 1L).atEndOfMonth();
    }

    private GoalProjectionStatus status(
        Money remaining, int remainingMonths, LocalDate projectedDate, Money effectiveRate, boolean breachesMinimum
    ) {
        if (lifecycle == FinancialGoalLifecycle.COMPLETED || remaining.isZero()) return GoalProjectionStatus.COMPLETED;
        if (lifecycle == FinancialGoalLifecycle.PAUSED) return GoalProjectionStatus.PAUSED;
        if (remainingMonths == 0) return GoalProjectionStatus.OVERDUE;
        if (effectiveRate.amount().signum() <= 0) return GoalProjectionStatus.INSUFFICIENT_DATA;
        if (breachesMinimum || projectedDate.isAfter(targetDate)) return GoalProjectionStatus.AT_RISK;
        return GoalProjectionStatus.ON_TRACK;
    }
}
