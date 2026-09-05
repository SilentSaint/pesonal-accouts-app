package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ManageBudgetUseCase;
import com.automaticexpense.tracker.application.port.out.BudgetNotificationPort;
import com.automaticexpense.tracker.application.port.out.BudgetRepository;
import com.automaticexpense.tracker.domain.CategoryBudget;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionType;

import java.time.format.DateTimeFormatter;
import java.util.*;

public class BudgetService implements ManageBudgetUseCase {

    private final BudgetRepository budgetRepository;
    private final BudgetNotificationPort notificationPort;

    public BudgetService(BudgetRepository budgetRepository, BudgetNotificationPort notificationPort) {
        this.budgetRepository = Objects.requireNonNull(budgetRepository, "budgetRepository cannot be null");
        this.notificationPort = Objects.requireNonNull(notificationPort, "notificationPort cannot be null");
    }

    @Override
    public CategoryBudget setBudget(String categoryId, String categoryName, String yearMonth, Money limitAmount) {
        Objects.requireNonNull(categoryId, "categoryId cannot be null");
        Objects.requireNonNull(limitAmount, "limitAmount cannot be null");

        String ym = (yearMonth != null && !yearMonth.isBlank()) ? yearMonth : java.time.LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM"));

        CategoryBudget existing = budgetRepository.findBudget(categoryId, ym).orElse(null);
        Money currentSpent = existing != null ? existing.currentSpend() : Money.zero(limitAmount.currency());

        CategoryBudget budget = new CategoryBudget(
            UUID.randomUUID().toString(),
            categoryId,
            categoryName != null ? categoryName : categoryId,
            ym,
            limitAmount,
            currentSpent
        );

        budgetRepository.save(budget);
        return budget;
    }

    @Override
    public void applyTransactionExpense(Transaction transaction) {
        if (transaction == null || transaction.type() != TransactionType.DEBIT || transaction.categoryId() == null) {
            return;
        }

        String ym = transaction.timestamp().format(DateTimeFormatter.ofPattern("yyyy-MM"));
        Optional<CategoryBudget> budgetOpt = budgetRepository.findBudget(transaction.categoryId(), ym);

        if (budgetOpt.isPresent()) {
            CategoryBudget budget = budgetOpt.get();
            boolean wasBelow80 = !budget.isThreshold80Reached();
            boolean wasBelow100 = !budget.isThreshold100Reached();

            budget.addSpend(transaction.netPersonalExpense());
            budgetRepository.save(budget);

            if (wasBelow80 && budget.isThreshold80Reached()) {
                notificationPort.publishBudgetAlert(budget, 80.0);
            }
            if (wasBelow100 && budget.isThreshold100Reached()) {
                notificationPort.publishBudgetAlert(budget, 100.0);
            }
        }
    }

    @Override
    public List<CategoryBudget> getBudgetsForMonth(String yearMonth) {
        String ym = (yearMonth != null && !yearMonth.isBlank()) ? yearMonth : java.time.LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM"));
        return budgetRepository.findBudgetsForMonth(ym);
    }
}
