package com.automaticexpense.tracker.application.port.in;

import java.time.Instant;
import java.util.List;

public record FinancialContextListView(Instant asOf, List<FinancialContextItemView> items) { }
