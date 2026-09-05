package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.CategoryBudget;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.Transaction;

import java.util.List;

public interface ManageBudgetUseCase {
    CategoryBudget setBudget(String categoryId, String categoryName, String yearMonth, Money limitAmount);
    void applyTransactionExpense(Transaction transaction);
    List<CategoryBudget> getBudgetsForMonth(String yearMonth);
}
