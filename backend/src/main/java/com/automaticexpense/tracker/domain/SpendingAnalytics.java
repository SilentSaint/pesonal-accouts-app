package com.automaticexpense.tracker.domain;

import java.util.List;
import java.util.Objects;

public record SpendingAnalytics(
    PeriodSpending currentPeriod,
    PeriodSpending previousPeriod,
    PeriodSpending yearOverYearPeriod,
    PeriodComparison monthOverMonth,
    PeriodComparison yearOverYear,
    Money rollingAverage,
    int transactionFrequency,
    Money averageTransactionValue,
    List<SpendingBreakdown> categoryBreakdown,
    List<SpendingBreakdown> merchantBreakdown,
    List<SpendingBreakdown> accountBreakdown,
    List<TransactionEvidence> largestPurchases,
    PeriodSpending highestPeriod,
    PeriodSpending lowestPeriod
) {
    public SpendingAnalytics {
        Objects.requireNonNull(currentPeriod, "currentPeriod cannot be null");
        Objects.requireNonNull(previousPeriod, "previousPeriod cannot be null");
        Objects.requireNonNull(yearOverYearPeriod, "yearOverYearPeriod cannot be null");
        Objects.requireNonNull(monthOverMonth, "monthOverMonth cannot be null");
        Objects.requireNonNull(yearOverYear, "yearOverYear cannot be null");
        Objects.requireNonNull(rollingAverage, "rollingAverage cannot be null");
        Objects.requireNonNull(averageTransactionValue, "averageTransactionValue cannot be null");
        categoryBreakdown = List.copyOf(categoryBreakdown == null ? List.of() : categoryBreakdown);
        merchantBreakdown = List.copyOf(merchantBreakdown == null ? List.of() : merchantBreakdown);
        accountBreakdown = List.copyOf(accountBreakdown == null ? List.of() : accountBreakdown);
        largestPurchases = List.copyOf(largestPurchases == null ? List.of() : largestPurchases);
        Objects.requireNonNull(highestPeriod, "highestPeriod cannot be null");
        Objects.requireNonNull(lowestPeriod, "lowestPeriod cannot be null");
    }
}
