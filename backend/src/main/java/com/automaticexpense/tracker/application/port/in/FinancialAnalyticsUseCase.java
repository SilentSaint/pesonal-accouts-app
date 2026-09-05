package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.AnalyticsSummary;

public interface FinancialAnalyticsUseCase {
    AnalyticsSummary generateMonthlyAnalytics(String yearMonth, String currency);
    String exportTransactionsToCsv(String yearMonth);
    String exportTransactionsToJson(String yearMonth);
}
