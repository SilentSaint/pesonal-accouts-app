package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.LoadFinancialSnapshotUseCase;
import com.automaticexpense.tracker.application.port.out.FinancialSnapshotRepository;
import com.automaticexpense.tracker.domain.EvidenceMetadata;
import com.automaticexpense.tracker.domain.FinancialSnapshot;
import com.automaticexpense.tracker.domain.FinancialSnapshotRequest;
import com.automaticexpense.tracker.domain.FormulaReference;
import com.automaticexpense.tracker.domain.IntelligenceClassification;
import com.automaticexpense.tracker.domain.IntelligenceResult;

import java.util.List;
import java.math.BigDecimal;
import java.util.Objects;

public final class FinancialSnapshotService implements LoadFinancialSnapshotUseCase {
    private static final FormulaReference FORMULA = new FormulaReference("financial-snapshot", "1.0.0");

    private final FinancialSnapshotRepository repository;

    public FinancialSnapshotService(FinancialSnapshotRepository repository) {
        this.repository = Objects.requireNonNull(repository, "repository cannot be null");
    }

    @Override
    public IntelligenceResult<FinancialSnapshot> load(FinancialSnapshotRequest request) {
        FinancialSnapshot snapshot = repository.load(Objects.requireNonNull(request, "request cannot be null"));
        return new IntelligenceResult<>(
            IntelligenceClassification.FACT,
            snapshot,
            snapshot.asOf(),
            snapshot.asOf(),
            BigDecimal.ONE,
            FORMULA,
            new EvidenceMetadata(snapshot.canonicalTransactions().size(), null),
            List.of("The snapshot is restricted to canonical ledger records available at the requested asOf instant."),
            List.of()
        );
    }
}
