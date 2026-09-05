package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.CardEmiPlan;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.TransactionId;

import java.util.List;
import java.util.Optional;

public interface ManageCardEmiUseCase {
    CardEmiPlan convertTransactionToEmi(
        TransactionId transactionId,
        int tenureMonths,
        double interestRatePercent,
        Money monthlyInstallment
    );

    CardEmiPlan recordInstallment(String planId);

    List<CardEmiPlan> getActivePlansForCard(String cardAccountId);

    List<CardEmiPlan> getAllActiveEmiPlans();

    Money getTotalMonthlyCommittedEmi(String currency);
}
