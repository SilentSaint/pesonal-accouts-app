package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.CardEmiPlan;

import java.util.List;
import java.util.Optional;

public interface CardEmiRepository {
    void save(CardEmiPlan emiPlan);
    Optional<CardEmiPlan> findEmiPlanById(String planId);
    List<CardEmiPlan> findActiveByCardId(String cardAccountId);
    List<CardEmiPlan> findAllActiveEmiPlans();
    List<CardEmiPlan> findAllEmiPlans();
}
