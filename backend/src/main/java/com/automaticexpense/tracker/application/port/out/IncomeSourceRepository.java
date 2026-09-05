package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.IncomeSource;

import java.util.List;
import java.util.Optional;

public interface IncomeSourceRepository {
    void save(IncomeSource source);

    /**
     * Replaces a source only while its persisted state is still pending. This prevents a recurring
     * detection refresh from reverting a concurrent confirmation or rejection.
     */
    boolean replaceIfPending(IncomeSource source);

    Optional<IncomeSource> findById(String incomeSourceId);

    Optional<IncomeSource> findBySuggestionKey(String suggestionKey);

    List<IncomeSource> findAll();
}
