package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.FinancialContextItem;

import java.util.List;
import java.util.Optional;

public interface FinancialContextRepository {
    void save(FinancialContextItem item);
    Optional<FinancialContextItem> findById(String id);
    List<FinancialContextItem> findAll();
    void delete(String id);
}
