package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.util.Objects;

public record ProactiveInsightRequest(
    String currency,
    BigDecimal relativeChangeThreshold,
    Money minimumAbsoluteChange,
    int minimumComparablePeriods
) {
    public ProactiveInsightRequest(String currency) {
        this(currency, new BigDecimal("0.25"), Money.of("500.00", currency), 3);
    }

    public ProactiveInsightRequest {
        if (currency == null || !currency.matches("[A-Z]{3}")) {
            throw new IllegalArgumentException("currency must be a three-letter uppercase ISO code");
        }
        Objects.requireNonNull(relativeChangeThreshold, "relativeChangeThreshold cannot be null");
        minimumAbsoluteChange = Objects.requireNonNull(
            minimumAbsoluteChange, "minimumAbsoluteChange cannot be null"
        );
        if (!currency.equals(minimumAbsoluteChange.currency())) {
            throw new IllegalArgumentException("minimumAbsoluteChange must use the request currency");
        }
        if (relativeChangeThreshold.signum() <= 0 || relativeChangeThreshold.compareTo(BigDecimal.ONE) > 0) {
            throw new IllegalArgumentException("relativeChangeThreshold must be greater than zero and at most one");
        }
        if (minimumComparablePeriods < 3 || minimumComparablePeriods > 12) {
            throw new IllegalArgumentException("minimumComparablePeriods must be between three and twelve");
        }
    }
}
