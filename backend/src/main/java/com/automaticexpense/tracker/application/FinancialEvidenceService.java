package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.LoadFinancialEvidenceUseCase;
import com.automaticexpense.tracker.application.port.out.FinancialEvidenceRepository;
import com.automaticexpense.tracker.domain.DrillDownReference;
import com.automaticexpense.tracker.domain.EvidenceMetadata;
import com.automaticexpense.tracker.domain.FinancialEvidencePage;
import com.automaticexpense.tracker.domain.FinancialEvidenceQuery;
import com.automaticexpense.tracker.domain.FormulaReference;
import com.automaticexpense.tracker.domain.IntelligenceClassification;
import com.automaticexpense.tracker.domain.IntelligenceResult;

import java.math.BigDecimal;
import java.util.List;
import java.util.Objects;

public final class FinancialEvidenceService implements LoadFinancialEvidenceUseCase {
    private static final FormulaReference FORMULA = new FormulaReference("financial-evidence", "1.0.0");

    private final FinancialEvidenceRepository repository;

    public FinancialEvidenceService(FinancialEvidenceRepository repository) {
        this.repository = Objects.requireNonNull(repository, "repository cannot be null");
    }

    @Override
    public IntelligenceResult<FinancialEvidencePage> load(FinancialEvidenceQuery query) {
        FinancialEvidencePage page = repository.load(Objects.requireNonNull(query, "query cannot be null"));
        return new IntelligenceResult<>(
            IntelligenceClassification.FACT,
            page,
            query.asOf(),
            query.asOf(),
            BigDecimal.ONE,
            FORMULA,
            new EvidenceMetadata(page.transactions().size(), new DrillDownReference(
                query.filters().period(),
                query.filters().currency(),
                query.filters().accountIds(),
                query.filters().categoryId(),
                query.filters().merchantName()
            )),
            List.of("Records are canonical debit transactions matching the supplied calculation filters."),
            List.of()
        );
    }
}
