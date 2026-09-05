package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class CategoryBudgetTest {

    @Test
    void shouldTrackBudgetSpendAndDetect80And100PercentThresholds() {
        CategoryBudget budget = new CategoryBudget(
            "b-1",
            "CAT_DINING",
            "Food & Dining",
            "2026-08",
            Money.of("10000.00", "INR"),
            Money.of("0.00", "INR")
        );

        assertThat(budget.getSpendPercentage()).isEqualTo(0.0);
        assertThat(budget.isThreshold80Reached()).isFalse();
        assertThat(budget.isThreshold100Reached()).isFalse();
        assertThat(budget.remainingBudget()).isEqualTo(Money.of("10000.00", "INR"));

        budget.addSpend(Money.of("8500.00", "INR"));
        assertThat(budget.getSpendPercentage()).isEqualTo(85.0);
        assertThat(budget.isThreshold80Reached()).isTrue();
        assertThat(budget.isThreshold100Reached()).isFalse();
        assertThat(budget.remainingBudget()).isEqualTo(Money.of("1500.00", "INR"));

        budget.addSpend(Money.of("2000.00", "INR"));
        assertThat(budget.getSpendPercentage()).isEqualTo(105.0);
        assertThat(budget.isThreshold100Reached()).isTrue();
        assertThat(budget.remainingBudget()).isEqualTo(Money.zero("INR"));
    }
}
