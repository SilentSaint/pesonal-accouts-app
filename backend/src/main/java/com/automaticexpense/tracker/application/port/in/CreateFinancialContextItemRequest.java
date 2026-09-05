package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.ContextProvenance;
import com.automaticexpense.tracker.domain.FinancialContextCapability;
import com.automaticexpense.tracker.domain.FinancialContextType;

import java.time.LocalDate;
import java.util.Map;
import java.util.Set;

public record CreateFinancialContextItemRequest(
    FinancialContextType type,
    String label,
    Map<String, String> values,
    Set<FinancialContextCapability> capabilities,
    ContextProvenance provenance,
    LocalDate effectiveFrom,
    LocalDate effectiveUntil
) { }
