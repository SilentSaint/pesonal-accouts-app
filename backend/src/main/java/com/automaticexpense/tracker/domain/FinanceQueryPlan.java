package com.automaticexpense.tracker.domain;

import java.util.Objects;

public record FinanceQueryPlan(FinanceQueryCapability capability, FinanceQueryFilters filters) {
    public FinanceQueryPlan {
        Objects.requireNonNull(capability, "capability cannot be null");
        Objects.requireNonNull(filters, "filters cannot be null");
    }
}
