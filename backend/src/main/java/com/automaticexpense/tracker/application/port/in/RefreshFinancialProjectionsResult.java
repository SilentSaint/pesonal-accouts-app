package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.ProactiveInsight;

import java.util.List;

public record RefreshFinancialProjectionsResult(List<ProactiveInsight> insights, int createdCount) {
    public RefreshFinancialProjectionsResult {
        insights = List.copyOf(insights == null ? List.of() : insights);
        if (createdCount < 0 || createdCount > insights.size()) {
            throw new IllegalArgumentException("createdCount must be within the insight count");
        }
    }
}
