package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.FinancialContextType;

import java.util.Map;

public record EligibleFinancialContextFields(
    String itemId,
    FinancialContextType type,
    Map<String, String> fields
) { }
