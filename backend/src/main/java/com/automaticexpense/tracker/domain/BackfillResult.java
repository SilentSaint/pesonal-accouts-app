package com.automaticexpense.tracker.domain;

import java.util.List;

public record BackfillResult(
    List<FinancialAccount> discoveredAccounts,
    List<Transaction> transactions,
    int totalEventsProcessed,
    int autoMergedCount
) {}
