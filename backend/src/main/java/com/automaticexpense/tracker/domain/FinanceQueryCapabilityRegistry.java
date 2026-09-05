package com.automaticexpense.tracker.domain;

import java.util.List;

public final class FinanceQueryCapabilityRegistry {
    private static final List<FinanceQueryCapability> REGISTERED = List.of(
        FinanceQueryCapability.SPENDING_TOTAL,
        FinanceQueryCapability.MERCHANT_BREAKDOWN,
        FinanceQueryCapability.CATEGORY_BREAKDOWN,
        FinanceQueryCapability.LARGEST_PURCHASES,
        FinanceQueryCapability.PERIOD_COMPARISON,
        FinanceQueryCapability.EVIDENCE_DRILL_DOWN
    );

    public List<FinanceQueryCapability> registeredCapabilities() {
        return REGISTERED;
    }

    public boolean contains(FinanceQueryCapability capability) {
        return REGISTERED.contains(capability);
    }
}
