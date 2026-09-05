package com.automaticexpense.tracker.domain;

import java.util.List;
import java.util.Objects;

public record AnalyticsSummary(
    String yearMonth,
    Money totalSpent,
    Money totalIncome,
    Money netSavings,
    int transactionCount,
    Money averageTransactionSize,
    String topVendorName,
    Money topVendorSpend,
    List<CategorySpendSummary> categoryBreakdown,
    List<String> aiInsights
) {
    public AnalyticsSummary {
        Objects.requireNonNull(yearMonth, "yearMonth cannot be null");
        Objects.requireNonNull(totalSpent, "totalSpent cannot be null");
        Objects.requireNonNull(totalIncome, "totalIncome cannot be null");
        Objects.requireNonNull(netSavings, "netSavings cannot be null");
        categoryBreakdown = categoryBreakdown != null ? List.copyOf(categoryBreakdown) : List.of();
        aiInsights = aiInsights != null ? List.copyOf(aiInsights) : List.of();
    }
}
