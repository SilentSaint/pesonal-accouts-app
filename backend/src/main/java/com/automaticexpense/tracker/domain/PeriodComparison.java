package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.util.Objects;

public record PeriodComparison(
    PeriodSpending baseline,
    Money absoluteChange,
    BigDecimal percentageChange
) {
    public PeriodComparison {
        Objects.requireNonNull(baseline, "baseline cannot be null");
        Objects.requireNonNull(absoluteChange, "absoluteChange cannot be null");
    }
}
