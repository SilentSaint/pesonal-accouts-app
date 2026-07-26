package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.out.AccountRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.FinancialAccount;

import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

public class InMemoryAccountRepository implements AccountRepository {
    private final Map<AccountId, FinancialAccount> accounts = new ConcurrentHashMap<>();

    @Override
    public void save(FinancialAccount account) {
        accounts.put(account.id(), account);
    }

    @Override
    public Optional<FinancialAccount> findById(AccountId id) {
        return Optional.ofNullable(accounts.get(id));
    }

    @Override
    public Optional<FinancialAccount> findByLastFourDigits(String lastFourDigits) {
        return accounts.values().stream()
            .filter(acc -> acc.lastFourDigits().equals(lastFourDigits))
            .findFirst();
    }
}
