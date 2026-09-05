package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.FinancialAnalyticsUseCase;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;

class FinancialAnalyticsUseCaseTest {

    private InMemoryTransactionRepository transactionRepository;
    private FinancialAnalyticsUseCase analyticsUseCase;

    @BeforeEach
    void setUp() {
        transactionRepository = new InMemoryTransactionRepository();
        analyticsUseCase = new FinancialAnalyticsService(transactionRepository);
    }

    @Test
    void shouldGenerateComprehensiveMonthlyAnalyticsAndAiInsights() {
        // Income
        transactionRepository.save(new Transaction(
            new TransactionId("tx-inc-1"),
            Money.of("75000.00", "INR"),
            TransactionType.CREDIT,
            LocalDateTime.of(2026, 8, 1, 9, 0),
            "Monthly Salary ACME Corp",
            new AccountId("acc-1"),
            "SALARY",
            IngestionSource.EMAIL,
            ReconciliationStatus.CONFIRMED,
            Money.of("75000.00", "INR")
        ));

        // Expenses
        transactionRepository.save(new Transaction(
            new TransactionId("tx-exp-1"),
            Money.of("12000.00", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 8, 3, 14, 0),
            "BigBasket Groceries",
            new AccountId("acc-1"),
            "GROCERIES",
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            Money.of("12000.00", "INR")
        ));

        transactionRepository.save(new Transaction(
            new TransactionId("tx-exp-2"),
            Money.of("8000.00", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 8, 10, 20, 0),
            "Taj Restaurant",
            new AccountId("acc-1"),
            "DINING",
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            Money.of("8000.00", "INR")
        ));

        AnalyticsSummary summary = analyticsUseCase.generateMonthlyAnalytics("2026-08", "INR");

        assertThat(summary.yearMonth()).isEqualTo("2026-08");
        assertThat(summary.totalIncome()).isEqualTo(Money.of("75000.00", "INR"));
        assertThat(summary.totalSpent()).isEqualTo(Money.of("20000.00", "INR"));
        assertThat(summary.netSavings()).isEqualTo(Money.of("55000.00", "INR"));
        assertThat(summary.transactionCount()).isEqualTo(3);
        assertThat(summary.topVendorName()).isEqualTo("BigBasket Groceries");
        assertThat(summary.categoryBreakdown()).hasSize(2);
        assertThat(summary.aiInsights()).isNotEmpty();
    }

    @Test
    void shouldExportTransactionsToCsvAndJson() {
        transactionRepository.save(new Transaction(
            new TransactionId("tx-exp-1"),
            Money.of("500.00", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 8, 3, 14, 0),
            "Swiggy",
            new AccountId("acc-1"),
            "DINING",
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            Money.of("500.00", "INR")
        ));

        String csv = analyticsUseCase.exportTransactionsToCsv("2026-08");
        assertThat(csv).contains("Id,Amount,Currency,Type,Date,Merchant,Category");
        assertThat(csv).contains("Swiggy");

        String json = analyticsUseCase.exportTransactionsToJson("2026-08");
        assertThat(json).contains("\"merchantName\": \"Swiggy\"");
    }

    private static class InMemoryTransactionRepository implements TransactionRepository {
        private final Map<String, Transaction> store = new HashMap<>();

        @Override
        public void save(Transaction transaction) {
            store.put(transaction.id().value(), transaction);
        }

        @Override
        public Optional<Transaction> findById(TransactionId id) {
            return Optional.ofNullable(store.get(id.value()));
        }

        @Override
        public List<Transaction> findByAccountId(AccountId accountId) {
            return store.values().stream().filter(t -> t.accountId().equals(accountId)).toList();
        }

        @Override
        public List<Transaction> findByReconciliationStatus(ReconciliationStatus status) {
            return store.values().stream().filter(t -> t.reconciliationStatus() == status).toList();
        }

        @Override
        public List<Transaction> findByAccountIdAndWindow(AccountId accountId, LocalDateTime startTime, LocalDateTime endTime) {
            return store.values().stream()
                .filter(t -> t.accountId().equals(accountId))
                .filter(t -> !t.timestamp().isBefore(startTime) && !t.timestamp().isAfter(endTime))
                .toList();
        }

        @Override
        public List<Transaction> findAllTransactions() {
            return new ArrayList<>(store.values());
        }

        @Override
        public void delete(TransactionId id) {
            store.remove(id.value());
        }
    }
}
