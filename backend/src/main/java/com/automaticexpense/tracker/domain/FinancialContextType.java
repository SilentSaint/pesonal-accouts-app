package com.automaticexpense.tracker.domain;

import java.util.Map;
import java.util.Set;
import java.math.BigDecimal;

public enum FinancialContextType {
    PREFERRED_MINIMUM_CASH_BALANCE(
        Set.of("amount", "currency"), Set.of("amount", "currency"),
        Set.of(FinancialContextCapability.CASH_FLOW_FORECAST, FinancialContextCapability.FINANCIAL_HEALTH),
        true
    ),
    RELATIONSHIP_ALIAS(
        Set.of("alias", "relationship"), Set.of("alias", "relationship"),
        Set.of(FinancialContextCapability.SHARED_EXPENSE_ANALYSIS),
        false
    ),
    SHARED_EXPENSE_RULE(
        Set.of("appliesTo", "splitPercentage"), Set.of("appliesTo", "splitPercentage"),
        Set.of(FinancialContextCapability.SHARED_EXPENSE_ANALYSIS),
        false
    ),
    MAJOR_PURCHASE_INTENTION(
        Set.of("plannedAmount", "currency", "targetDate"), Set.of("plannedAmount", "currency", "targetDate"),
        Set.of(FinancialContextCapability.CASH_FLOW_FORECAST, FinancialContextCapability.FINANCIAL_HEALTH),
        false
    ),
    ANALYSIS_PREFERENCE(
        Set.of("analysisMode"), Set.of("analysisMode"),
        Set.of(FinancialContextCapability.FINANCIAL_ANALYSIS),
        true
    );

    private final Set<String> requiredFields;
    private final Set<String> allowedFields;
    private final Set<FinancialContextCapability> allowedCapabilities;
    private final boolean singleton;

    FinancialContextType(
        Set<String> requiredFields,
        Set<String> allowedFields,
        Set<FinancialContextCapability> allowedCapabilities,
        boolean singleton
    ) {
        this.requiredFields = requiredFields;
        this.allowedFields = allowedFields;
        this.allowedCapabilities = allowedCapabilities;
        this.singleton = singleton;
    }

    public void validateValues(Map<String, String> values) {
        if (values == null || !values.keySet().containsAll(requiredFields)
            || !allowedFields.containsAll(values.keySet())
            || values.values().stream().anyMatch(value -> value == null || value.isBlank())) {
            throw new IllegalArgumentException("Invalid values for context type " + name());
        }
        switch (this) {
            case PREFERRED_MINIMUM_CASH_BALANCE -> validatePositiveDecimal(values.get("amount"));
            case SHARED_EXPENSE_RULE -> {
                BigDecimal split = parseDecimal(values.get("splitPercentage"));
                if (split.compareTo(BigDecimal.ZERO) <= 0 || split.compareTo(BigDecimal.valueOf(100)) > 0) {
                    throw new IllegalArgumentException("splitPercentage must be greater than zero and at most 100");
                }
            }
            case MAJOR_PURCHASE_INTENTION -> {
                validatePositiveDecimal(values.get("plannedAmount"));
                java.time.LocalDate.parse(values.get("targetDate"));
            }
            case ANALYSIS_PREFERENCE -> {
                if (!Set.of("CONSERVATIVE", "BALANCED", "DETAILED").contains(values.get("analysisMode"))) {
                    throw new IllegalArgumentException("analysisMode must be CONSERVATIVE, BALANCED, or DETAILED");
                }
            }
            case RELATIONSHIP_ALIAS -> { }
        }
    }

    public Set<FinancialContextCapability> allowedCapabilities() {
        return allowedCapabilities;
    }

    public boolean singleton() {
        return singleton;
    }

    public Set<String> minimizedFields() {
        return allowedFields;
    }

    private static void validatePositiveDecimal(String value) {
        if (parseDecimal(value).compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Amount must be greater than zero");
        }
    }

    private static BigDecimal parseDecimal(String value) {
        try {
            return new BigDecimal(value);
        } catch (NumberFormatException exception) {
            throw new IllegalArgumentException("Expected a numeric context value", exception);
        }
    }
}
