package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.FinancialAccount;

import java.util.Optional;

public interface AccountRepository {
    void save(FinancialAccount account);
    Optional<FinancialAccount> findById(AccountId id);
    Optional<FinancialAccount> findByLastFourDigits(String lastFourDigits);
}
