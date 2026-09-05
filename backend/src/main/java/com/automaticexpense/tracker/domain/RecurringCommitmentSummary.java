package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.util.List;
import java.util.Objects;

public record RecurringCommitmentSummary(
    java.time.LocalDate asOf,
    String formulaId,
    IntelligenceClassification classification,
    Money confirmedFixedMonthlyCost,
    Money variableMonthlyCost,
    Money confirmedFixedMonthlyIncome,
    BigDecimal fixedCostRatio,
    int confirmedCommitmentCount,
    int variableCommitmentCount,
    List<String> warnings
) {
    public RecurringCommitmentSummary {
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(formulaId, "formulaId cannot be null");
        Objects.requireNonNull(classification, "classification cannot be null");
        Objects.requireNonNull(confirmedFixedMonthlyCost, "confirmedFixedMonthlyCost cannot be null");
        Objects.requireNonNull(variableMonthlyCost, "variableMonthlyCost cannot be null");
        Objects.requireNonNull(confirmedFixedMonthlyIncome, "confirmedFixedMonthlyIncome cannot be null");
        warnings = List.copyOf(Objects.requireNonNull(warnings, "warnings cannot be null"));
    }
}
