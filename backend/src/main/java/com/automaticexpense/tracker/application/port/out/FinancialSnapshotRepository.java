package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.FinancialSnapshot;
import com.automaticexpense.tracker.domain.FinancialSnapshotRequest;

/**
 * Loads a principal-scoped, canonical ledger view at the requested watermark.
 */
public interface FinancialSnapshotRepository {
    FinancialSnapshot load(FinancialSnapshotRequest request);
}
