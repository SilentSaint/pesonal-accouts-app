package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.VendorCategoryRule;

import java.util.List;
import java.util.Optional;

public interface VendorRuleRepository {
    void save(VendorCategoryRule rule);
    Optional<VendorCategoryRule> findByPayeeKey(String payeeKey);
    List<VendorCategoryRule> findAll();
}
