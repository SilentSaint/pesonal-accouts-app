package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ManageBudgetUseCase;
import com.automaticexpense.tracker.application.port.out.BudgetNotificationPort;
import com.automaticexpense.tracker.application.port.out.BudgetRepository;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;

class ManageBudgetUseCaseTest {

    private InMemoryBudgetRepository budgetRepository;
    private MockBudgetNotificationPort notificationPort;
    private ManageBudgetUseCase budgetUseCase;

    @BeforeEach
    void setUp() {
        budgetRepository = new InMemoryBudgetRepository();
        notificationPort = new MockBudgetNotificationPort();
        budgetUseCase = new BudgetService(budgetRepository, notificationPort);
    }

    @Test
    void shouldSetMonthlyBudgetForCategory() {
        CategoryBudget budget = budgetUseCase.setBudget(
            "CAT_GROCERIES",
            "Groceries",
            "2026-08",
            Money.of("15000.00", "INR")
        );

        assertThat(budget.categoryId()).isEqualTo("CAT_GROCERIES");
        assertThat(budget.limitAmount()).isEqualTo(Money.of("15000.00", "INR"));

        Optional<CategoryBudget> saved = budgetRepository.findBudget("CAT_GROCERIES", "2026-08");
        assertThat(saved).isPresent();
    }

    @Test
    void shouldApplyTransactionExpenseAndTriggerAlertsAt80Percent() {
        budgetUseCase.setBudget(
            "CAT_DINING",
            "Dining",
            "2026-08",
            Money.of("10000.00", "INR")
        );

        Transaction tx = new Transaction(
            new TransactionId("tx-dining-1"),
            Money.of("8500.00", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 8, 15, 20, 0),
            "BBQ Nation",
            new AccountId("acc-1"),
            "CAT_DINING",
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            Money.of("8500.00", "INR")
        );

        budgetUseCase.applyTransactionExpense(tx);

        CategoryBudget updated = budgetRepository.findBudget("CAT_DINING", "2026-08").orElseThrow();
        assertThat(updated.currentSpend()).isEqualTo(Money.of("8500.00", "INR"));
        assertThat(updated.isThreshold80Reached()).isTrue();

        assertThat(notificationPort.notifiedBudgets).hasSize(1);
        assertThat(notificationPort.notifiedBudgets.get(0).categoryId()).isEqualTo("CAT_DINING");
    }

    private static class InMemoryBudgetRepository implements BudgetRepository {
        private final Map<String, CategoryBudget> store = new HashMap<>();

        private String key(String catId, String ym) {
            return catId + "#" + ym;
        }

        @Override
        public void save(CategoryBudget budget) {
            store.put(key(budget.categoryId(), budget.yearMonth()), budget);
        }

        @Override
        public Optional<CategoryBudget> findBudget(String categoryId, String yearMonth) {
            return Optional.ofNullable(store.get(key(categoryId, yearMonth)));
        }

        @Override
        public List<CategoryBudget> findBudgetsForMonth(String yearMonth) {
            return store.values().stream()
                .filter(b -> b.yearMonth().equals(yearMonth))
                .toList();
        }

        @Override
        public List<CategoryBudget> findAllBudgets() {
            return new ArrayList<>(store.values());
        }
    }

    private static class MockBudgetNotificationPort implements BudgetNotificationPort {
        final List<CategoryBudget> notifiedBudgets = new ArrayList<>();

        @Override
        public void publishBudgetAlert(CategoryBudget budget, double thresholdPercentage) {
            notifiedBudgets.add(budget);
        }
    }
}
