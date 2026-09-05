package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.FinancialContextItem;
import com.automaticexpense.tracker.domain.FinancialContextItemStatus;

import java.util.List;

public record FinancialContextItemView(
    FinancialContextItem item,
    FinancialContextItemStatus status,
    List<String> conflictIds
) { }
