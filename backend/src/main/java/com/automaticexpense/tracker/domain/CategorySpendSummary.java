package com.automaticexpense.tracker.domain;

import java.util.List;
import java.util.Objects;

public record CategorySpendSummary(
    String categoryId,
    String categoryName,
    Money totalSpent,
    double percentageOfTotal
) {
    public CategorySpendSummary {
        Objects.requireNonNull(categoryId, "categoryId cannot be null");
        Objects.requireNonNull(categoryName, "categoryName cannot be null");
        Objects.requireNonNull(totalSpent, "totalSpent cannot be null");
    }
}
