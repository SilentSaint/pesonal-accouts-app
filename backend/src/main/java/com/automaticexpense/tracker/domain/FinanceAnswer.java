package com.automaticexpense.tracker.domain;

import java.time.Instant;
import java.util.List;
import java.util.Objects;

public record FinanceAnswer(
    IntelligenceClassification classification,
    String observation,
    Instant asOf,
    FormulaReference formula,
    EvidenceMetadata evidence,
    List<String> assumptions,
    List<IntelligenceWarning> warnings
) {
    public FinanceAnswer {
        Objects.requireNonNull(classification, "classification cannot be null");
        if (observation == null || observation.isBlank()) {
            throw new IllegalArgumentException("observation cannot be blank");
        }
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(formula, "formula cannot be null");
        Objects.requireNonNull(evidence, "evidence cannot be null");
        assumptions = List.copyOf(assumptions == null ? List.of() : assumptions);
        warnings = List.copyOf(warnings == null ? List.of() : warnings);
    }
}
