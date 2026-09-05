package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.out.VendorRuleRepository;
import com.automaticexpense.tracker.domain.VendorCategoryRule;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

final class InMemoryVendorRuleRepository implements VendorRuleRepository {
    private final Map<String, VendorCategoryRule> rules = new ConcurrentHashMap<>();

    @Override
    public void save(VendorCategoryRule rule) {
        rules.put(rule.payeeKey(), rule);
    }

    @Override
    public Optional<VendorCategoryRule> findByPayeeKey(String payeeKey) {
        return Optional.ofNullable(rules.get(payeeKey));
    }

    @Override
    public List<VendorCategoryRule> findAll() {
        return List.copyOf(rules.values());
    }
}
