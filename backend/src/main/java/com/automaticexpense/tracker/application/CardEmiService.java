package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ManageCardEmiUseCase;
import com.automaticexpense.tracker.application.port.out.CardEmiRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.*;

import java.time.LocalDate;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public class CardEmiService implements ManageCardEmiUseCase {

    private final CardEmiRepository cardEmiRepository;
    private final TransactionRepository transactionRepository;

    public CardEmiService(CardEmiRepository cardEmiRepository, TransactionRepository transactionRepository) {
        this.cardEmiRepository = Objects.requireNonNull(cardEmiRepository, "cardEmiRepository cannot be null");
        this.transactionRepository = Objects.requireNonNull(transactionRepository, "transactionRepository cannot be null");
    }

    @Override
    public CardEmiPlan convertTransactionToEmi(
        TransactionId transactionId,
        int tenureMonths,
        double interestRatePercent,
        Money monthlyInstallment
    ) {
        Objects.requireNonNull(transactionId, "transactionId cannot be null");
        Objects.requireNonNull(monthlyInstallment, "monthlyInstallment cannot be null");

        Transaction tx = transactionRepository.findById(transactionId)
            .orElseThrow(() -> new IllegalArgumentException("Transaction not found: " + transactionId.value()));

        CardEmiPlan plan = new CardEmiPlan(
            UUID.randomUUID().toString(),
            tx.accountId().value(),
            tx.merchantName(),
            tx.amount(),
            monthlyInstallment,
            interestRatePercent,
            tenureMonths,
            0,
            LocalDate.now().plusMonths(1)
        );

        cardEmiRepository.save(plan);
        return plan;
    }

    @Override
    public CardEmiPlan recordInstallment(String planId) {
        Objects.requireNonNull(planId, "planId cannot be null");

        CardEmiPlan plan = cardEmiRepository.findEmiPlanById(planId)
            .orElseThrow(() -> new IllegalArgumentException("EMI plan not found: " + planId));

        plan.recordInstallment();
        cardEmiRepository.save(plan);
        return plan;
    }

    @Override
    public List<CardEmiPlan> getActivePlansForCard(String cardAccountId) {
        Objects.requireNonNull(cardAccountId, "cardAccountId cannot be null");
        return cardEmiRepository.findActiveByCardId(cardAccountId);
    }

    @Override
    public List<CardEmiPlan> getAllActiveEmiPlans() {
        return cardEmiRepository.findAllActiveEmiPlans();
    }

    @Override
    public Money getTotalMonthlyCommittedEmi(String currency) {
        List<CardEmiPlan> active = cardEmiRepository.findAllActiveEmiPlans();
        Money total = Money.zero(currency);
        for (CardEmiPlan plan : active) {
            if (plan.monthlyInstallment().currency().equalsIgnoreCase(currency)) {
                total = total.add(plan.monthlyInstallment());
            }
        }
        return total;
    }
}
