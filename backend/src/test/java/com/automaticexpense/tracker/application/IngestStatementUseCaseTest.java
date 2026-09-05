package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.IngestStatementWebhookUseCase;
import com.automaticexpense.tracker.application.port.in.StatementIngestionSummary;
import com.automaticexpense.tracker.application.port.out.AccountRepository;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;

class IngestStatementUseCaseTest {

    private InMemoryAccountRepository accountRepository;
    private InMemoryTransactionRepository transactionRepository;
    private InMemoryBillRepository billRepository;
    private IngestStatementWebhookUseCase ingestStatementUseCase;

    @BeforeEach
    void setUp() {
        accountRepository = new InMemoryAccountRepository();
        transactionRepository = new InMemoryTransactionRepository();
        billRepository = new InMemoryBillRepository();

        IngestTransactionService ingestTransactionService = new IngestTransactionService(
            accountRepository,
            transactionRepository,
            new InMemoryVendorRuleRepository()
        );

        ingestStatementUseCase = new IngestStatementService(
            new StatementParser(),
            accountRepository,
            billRepository,
            ingestTransactionService,
            transactionRepository
        );
    }

    @Test
    void shouldIngestStatementExtractBillAndDeduplicateTransactions() {
        // Pre-existing account
        FinancialAccount hdfcCard = new FinancialAccount(
            new AccountId("acc-card-4321"),
            "HDFC Credit Card",
            AccountType.CREDIT_CARD,
            "4321",
            "INR",
            Money.zero("INR")
        );
        accountRepository.save(hdfcCard);

        // Pre-existing real-time SMS transaction
        Transaction existingSmsTx = new Transaction(
            new TransactionId("sms-tx-1"),
            Money.of("450.00", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 8, 1, 12, 0),
            "Swiggy",
            hdfcCard.id(),
            "DINING",
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            Money.of("450.00", "INR")
        );
        transactionRepository.save(existingSmsTx);

        String statementPayload = """
            Account: HDFC Credit Card Ending 4321
            Statement Date: 2026-08-15
            Total Due: 34500.00 INR
            Min Due: 2000.00 INR
            Payment Due Date: 2026-09-05
            ---
            2026-08-01,Swiggy,450.00,INR,DEBIT,REF-SWIGGY-101
            2026-08-03,Amazon,12499.00,INR,DEBIT,REF-AMZN-202
            """;

        StatementIngestionSummary summary = ingestStatementUseCase.ingestStatementPayload(
            statementPayload,
            IngestionSource.EMAIL
        );

        assertThat(summary.totalParsedTransactions()).isEqualTo(2);
        assertThat(summary.newTransactionsIngested()).isEqualTo(1);
        assertThat(summary.duplicatesMerged()).isEqualTo(1);
        assertThat(summary.billStatement()).isNotNull();
        assertThat(summary.billStatement().totalAmount()).isEqualTo(Money.of("34500.00", "INR"));

        // Verify bill saved
        List<BillStatement> bills = billRepository.findAllBills();
        assertThat(bills).hasSize(1);
    }

    @Test
    void shouldUpsertTheSameAccountStatementCycleWithoutDoubleCountingCashFlow() {
        FinancialAccount hdfcCard = new FinancialAccount(
            new AccountId("acc-card-4321"),
            "HDFC Credit Card",
            AccountType.CREDIT_CARD,
            "4321",
            "INR",
            Money.zero("INR")
        );
        accountRepository.save(hdfcCard);

        String originalStatement = """
            Account: HDFC Credit Card Ending 4321
            Statement Date: 2026-08-15
            Total Due: 34500.00 INR
            Min Due: 2000.00 INR
            Payment Due Date: 2026-09-05
            ---
            2026-08-03,Amazon,12499.00,INR,DEBIT,REF-AMZN-202
            """;
        String correctedStatement = originalStatement.replace("Min Due: 2000.00", "Min Due: 2500.00");

        StatementIngestionSummary first = ingestStatementUseCase.ingestStatementPayload(originalStatement, IngestionSource.EMAIL);
        StatementIngestionSummary second = ingestStatementUseCase.ingestStatementPayload(correctedStatement, IngestionSource.EMAIL);

        assertThat(second.billStatement().id()).isEqualTo(first.billStatement().id());
        assertThat(billRepository.findAllBills()).hasSize(1);
        assertThat(second.billStatement().minimumDue()).isEqualTo(Money.of("2500.00", "INR"));
        assertThat(second.billStatement().billingCycle().toString()).isEqualTo("2026-08");
        assertThat(accountRepository.findById(hdfcCard.id()).orElseThrow().currentBalance())
            .isEqualTo(Money.of("-12499.00", "INR"));
    }

    private static class InMemoryAccountRepository implements AccountRepository {
        private final Map<String, FinancialAccount> store = new HashMap<>();

        @Override
        public Optional<FinancialAccount> findByLastFourDigits(String lastFourDigits) {
            return store.values().stream().filter(a -> a.lastFourDigits().equals(lastFourDigits)).findFirst();
        }

        @Override
        public Optional<FinancialAccount> findById(AccountId id) {
            return Optional.ofNullable(store.get(id.value()));
        }

        @Override
        public void save(FinancialAccount account) {
            store.put(account.id().value(), account);
        }
    }

    private static class InMemoryBillRepository implements BillRepository {
        private final Map<String, BillStatement> store = new HashMap<>();

        @Override
        public void save(BillStatement billStatement) {
            store.put(billStatement.id(), billStatement);
        }

        @Override
        public Optional<BillStatement> findBillById(String billId) {
            return Optional.ofNullable(store.get(billId));
        }

        @Override
        public List<BillStatement> findPendingBills() {
            return store.values().stream().filter(b -> !b.isPaid()).toList();
        }

        @Override
        public List<BillStatement> findAllBills() {
            return new ArrayList<>(store.values());
        }
    }
}
