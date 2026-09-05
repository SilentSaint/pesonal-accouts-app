package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.FinancialGoal;

import java.util.List;
import java.util.Optional;

public interface FinancialGoalRepository {
    void save(FinancialGoal goal);

    Optional<FinancialGoal> findById(String id);

    List<FinancialGoal> findAll();

    void deleteById(String id);
}
