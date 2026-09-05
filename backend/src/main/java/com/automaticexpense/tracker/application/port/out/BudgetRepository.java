package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.CategoryBudget;

import java.util.List;
import java.util.Optional;

public interface BudgetRepository {
    void save(CategoryBudget budget);
    Optional<CategoryBudget> findBudget(String categoryId, String yearMonth);
    List<CategoryBudget> findBudgetsForMonth(String yearMonth);
    List<CategoryBudget> findAllBudgets();
}
