package com.automaticexpense.tracker.domain;

import java.time.Instant;
import java.math.BigDecimal;
import java.util.List;
import java.util.Objects;

public record IntelligenceResult<T>(
    IntelligenceClassification classification,
    T value,
    Instant asOf,
    Instant freshnessAsOf,
    BigDecimal confidence,
    FormulaReference formula,
    EvidenceMetadata evidence,
    List<String> assumptions,
    List<IntelligenceWarning> warnings
) {
    public IntelligenceResult {
        Objects.requireNonNull(classification, "classification cannot be null");
        Objects.requireNonNull(value, "value cannot be null");
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(freshnessAsOf, "freshnessAsOf cannot be null");
        Objects.requireNonNull(confidence, "confidence cannot be null");
        if (confidence.compareTo(BigDecimal.ZERO) < 0 || confidence.compareTo(BigDecimal.ONE) > 0) {
            throw new IllegalArgumentException("confidence must be between zero and one");
        }
        Objects.requireNonNull(formula, "formula cannot be null");
        Objects.requireNonNull(evidence, "evidence cannot be null");
        assumptions = List.copyOf(assumptions == null ? List.of() : assumptions);
        warnings = List.copyOf(warnings == null ? List.of() : warnings);
    }
}
