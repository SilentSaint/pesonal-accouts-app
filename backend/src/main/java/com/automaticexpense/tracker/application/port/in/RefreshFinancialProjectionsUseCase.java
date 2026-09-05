package com.automaticexpense.tracker.application.port.in;

public interface RefreshFinancialProjectionsUseCase {
    RefreshFinancialProjectionsResult refresh(RefreshFinancialProjectionsRequest request);
}
