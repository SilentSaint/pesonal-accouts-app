package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.FinancialContextCapability;

import java.time.LocalDate;
import java.util.Map;
import java.util.Set;

public record UpdateFinancialContextItemRequest(
    String label,
    Map<String, String> values,
    Set<FinancialContextCapability> capabilities,
    LocalDate effectiveFrom,
    LocalDate effectiveUntil
) { }
