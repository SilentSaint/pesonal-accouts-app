package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.FinancialSnapshot;
import com.automaticexpense.tracker.domain.FinancialSnapshotRequest;
import com.automaticexpense.tracker.domain.IntelligenceResult;

public interface LoadFinancialSnapshotUseCase {
    IntelligenceResult<FinancialSnapshot> load(FinancialSnapshotRequest request);
}
