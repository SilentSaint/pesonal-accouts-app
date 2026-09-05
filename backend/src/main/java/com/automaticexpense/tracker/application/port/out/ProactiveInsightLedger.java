package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.FinancialSnapshot;

import java.time.Instant;
import java.time.ZoneId;

public interface ProactiveInsightLedger {
    FinancialSnapshot load(String userId, Instant asOf, ZoneId timezone);
}
