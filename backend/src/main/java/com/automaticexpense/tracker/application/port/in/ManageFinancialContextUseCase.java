package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.FinancialContextCapability;
import com.automaticexpense.tracker.domain.FinancialContextItem;

import java.time.Instant;
import java.util.List;

public interface ManageFinancialContextUseCase {
    FinancialContextItem create(CreateFinancialContextItemRequest request);
    FinancialContextItem update(String id, UpdateFinancialContextItemRequest request);
    FinancialContextItem deactivate(String id);
    void delete(String id);
    FinancialContextListView list(Instant asOf);
    List<EligibleFinancialContextFields> selectEligibleFields(FinancialContextCapability capability, Instant asOf);
}
