package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ManageCardEmiUseCase;
import com.automaticexpense.tracker.application.port.out.CardEmiRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ManageCardEmiUseCaseTest {

    private InMemoryCardEmiRepository cardEmiRepository;
    private InMemoryTransactionRepository transactionRepository;
    private ManageCardEmiUseCase cardEmiUseCase;

    @BeforeEach
    void setUp() {
        cardEmiRepository = new InMemoryCardEmiRepository();
        transactionRepository = new InMemoryTransactionRepository();
        cardEmiUseCase = new CardEmiService(cardEmiRepository, transactionRepository);
    }

    @Test
    void shouldConvertCardTransactionToEmiPlan() {
        Transaction tx = new Transaction(
            new TransactionId("tx-croma-1"),
            Money.of("48000.00", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.now(),
            "Croma Electronics",
            new AccountId("card-sbi-9988"),
            "ELECTRONICS",
            IngestionSource.EMAIL,
            ReconciliationStatus.CONFIRMED,
            Money.of("48000.00", "INR")
        );
        transactionRepository.save(tx);

        CardEmiPlan plan = cardEmiUseCase.convertTransactionToEmi(
            tx.id(),
            6,
            14.0,
            Money.of("8500.00", "INR")
        );

        assertThat(plan.id()).isNotBlank();
        assertThat(plan.merchantName()).isEqualTo("Croma Electronics");
        assertThat(plan.cardAccountId()).isEqualTo("card-sbi-9988");
        assertThat(plan.totalTenureMonths()).isEqualTo(6);
        assertThat(plan.monthlyInstallment()).isEqualTo(Money.of("8500.00", "INR"));
        assertThat(plan.status()).isEqualTo(EmiPlanStatus.ACTIVE);

        Optional<CardEmiPlan> saved = cardEmiRepository.findEmiPlanById(plan.id());
        assertThat(saved).isPresent();
    }

    @Test
    void shouldCalculateTotalMonthlyCommittedEmiAcrossActivePlans() {
        cardEmiRepository.save(new CardEmiPlan(
            "emi-1",
            "card-1",
            "Amazon",
            Money.of("30000.00", "INR"),
            Money.of("5200.00", "INR"),
            13.0,
            6,
            1,
            java.time.LocalDate.now().plusDays(10)
        ));

        cardEmiRepository.save(new CardEmiPlan(
            "emi-2",
            "card-2",
            "Flipkart",
            Money.of("20000.00", "INR"),
            Money.of("3500.00", "INR"),
            14.0,
            6,
            2,
            java.time.LocalDate.now().plusDays(15)
        ));

        Money totalCommitted = cardEmiUseCase.getTotalMonthlyCommittedEmi("INR");
        assertThat(totalCommitted).isEqualTo(Money.of("8700.00", "INR"));
    }

    private static class InMemoryCardEmiRepository implements CardEmiRepository {
        private final Map<String, CardEmiPlan> store = new HashMap<>();

        @Override
        public void save(CardEmiPlan emiPlan) {
            store.put(emiPlan.id(), emiPlan);
        }

        @Override
        public Optional<CardEmiPlan> findEmiPlanById(String planId) {
            return Optional.ofNullable(store.get(planId));
        }

        @Override
        public List<CardEmiPlan> findActiveByCardId(String cardAccountId) {
            return store.values().stream()
                .filter(p -> p.cardAccountId().equals(cardAccountId) && !p.isCompleted())
                .toList();
        }

        @Override
        public List<CardEmiPlan> findAllActiveEmiPlans() {
            return store.values().stream()
                .filter(p -> !p.isCompleted())
                .toList();
        }

        @Override
        public List<CardEmiPlan> findAllEmiPlans() {
            return new ArrayList<>(store.values());
        }
    }
}
