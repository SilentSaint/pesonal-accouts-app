package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.CategoryBudget;

public interface BudgetNotificationPort {
    void publishBudgetAlert(CategoryBudget budget, double thresholdPercentage);
}
