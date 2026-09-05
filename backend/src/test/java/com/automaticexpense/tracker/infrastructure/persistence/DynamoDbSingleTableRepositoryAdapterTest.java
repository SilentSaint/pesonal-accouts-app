package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class DynamoDbSingleTableRepositoryAdapterTest {

    private DynamoDbSingleTableRepositoryAdapter adapter;

    @BeforeEach
    void setUp() {
        adapter = new DynamoDbSingleTableRepositoryAdapter("user-123");
    }

    @Test
    void shouldSerializeAndPersistFinancialAccountUsingSingleTableKeys() {
        FinancialAccount account = new FinancialAccount(
            new AccountId("acc-99"),
            "SBI Savings",
            AccountType.SAVINGS,
            "9999",
            "INR",
            new Money(new BigDecimal("15000.00"), "INR")
        );

        Map<String, String> item = DynamoDbItem.fromAccount("user-123", account);
        assertThat(item.get("PK")).isEqualTo("USER#user-123");
        assertThat(item.get("SK")).isEqualTo("ACC#acc-99");
        assertThat(item.get("entityType")).isEqualTo("ACCOUNT");

        adapter.save(account);

        FinancialAccount retrieved = adapter.findById(new AccountId("acc-99")).orElseThrow();
        assertThat(retrieved.name()).isEqualTo("SBI Savings");
        assertThat(retrieved.currentBalance().amount()).isEqualByComparingTo("15000.00");
    }

    @Test
    void shouldSerializeAndPersistTransactionUsingSingleTableKeys() {
        Transaction transaction = new Transaction(
            new TransactionId("txn-100"),
            new Money(new BigDecimal("1200.00"), "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 7, 26, 15, 30),
            "Uber",
            new AccountId("acc-99"),
            "Transportation",
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            new Money(new BigDecimal("1200.00"), "INR")
        );

        Map<String, String> item = DynamoDbItem.fromTransaction("user-123", transaction);
        assertThat(item.get("PK")).isEqualTo("USER#user-123");
        assertThat(item.get("SK")).startsWith("TXN#2026-07-26T15:30#txn-100");
        assertThat(item.get("entityType")).isEqualTo("TRANSACTION");

        adapter.save(transaction);

        List<Transaction> accountTxns = adapter.findByAccountId(new AccountId("acc-99"));
        assertThat(accountTxns).hasSize(1);
        assertThat(accountTxns.get(0).merchantName()).isEqualTo("Uber");
    }

    @Test
    void preservesEveryEditedReviewFieldWhenATransactionIsStoredAndReloaded() {
        Transaction transaction = new Transaction(
            new TransactionId("txn-review-00000001"),
            Money.of("913.42", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 8, 29, 6, 0),
            "Green Market",
            new AccountId("acc-1234"),
            "Groceries",
            "Fruits & Vegetables",
            IngestionSource.MANUAL,
            ReconciliationStatus.CONFIRMED,
            Money.of("900.00", "INR"),
            "•••• 1234",
            "upi-12345678",
            "edited receipt",
            "•••• 9876"
        );

        adapter.save(transaction);

        Transaction reloaded = adapter.findByAccountId(new AccountId("acc-1234"))
            .stream()
            .filter(item -> item.id().equals(transaction.id()))
            .findFirst()
            .orElseThrow();
        assertThat(reloaded.amount()).isEqualTo(Money.of("913.42", "INR"));
        assertThat(reloaded.type()).isEqualTo(TransactionType.DEBIT);
        assertThat(reloaded.timestamp()).isEqualTo(LocalDateTime.of(2026, 8, 29, 6, 0));
        assertThat(reloaded.merchantName()).isEqualTo("Green Market");
        assertThat(reloaded.accountId()).isEqualTo(new AccountId("acc-1234"));
        assertThat(reloaded.categoryId()).isEqualTo("Groceries");
        assertThat(reloaded.subCategory()).isEqualTo("Fruits & Vegetables");
        assertThat(reloaded.ingestionSource()).isEqualTo(IngestionSource.MANUAL);
        assertThat(reloaded.reconciliationStatus()).isEqualTo(ReconciliationStatus.CONFIRMED);
        assertThat(reloaded.netPersonalExpense()).isEqualTo(Money.of("900.00", "INR"));
        assertThat(reloaded.accountMask()).isEqualTo("•••• 1234");
        assertThat(reloaded.referenceNumber()).isEqualTo("upi-12345678");
        assertThat(reloaded.rawSnippet()).isEqualTo("edited receipt");
        assertThat(reloaded.transferCounterpartMask()).isEqualTo("•••• 9876");
    }

    @Test
    void atomicallyReplacesAnAmbiguousCandidateWithAnEnrichedCanonicalTransaction() {
        Transaction canonical = new Transaction(
            new TransactionId("txn-sms-001"), Money.of("850.00", "INR"),
            TransactionType.DEBIT, LocalDateTime.of(2026, 8, 29, 10, 0),
            "Bundl Tech", new AccountId("acc-1234"), null, IngestionSource.SMS,
            ReconciliationStatus.NEEDS_REVIEW, Money.of("850.00", "INR")
        );
        Transaction candidate = new Transaction(
            new TransactionId("txn-email-001"), Money.of("850.00", "INR"),
            TransactionType.DEBIT, LocalDateTime.of(2026, 8, 29, 10, 8),
            "Swiggy Pay", new AccountId("acc-1234"), null, IngestionSource.EMAIL,
            ReconciliationStatus.NEEDS_REVIEW, Money.of("850.00", "INR")
        ).withPotentialDuplicateOf(canonical.id());
        adapter.save(canonical);
        adapter.save(candidate);

        boolean merged = adapter.mergeCanonically(
            canonical.enrichedWith(IngestionSource.EMAIL), candidate
        );

        assertThat(merged).isTrue();
        assertThat(adapter.findById(candidate.id())).isEmpty();
        assertThat(adapter.findById(canonical.id()))
            .hasValueSatisfying(reloaded -> {
                assertThat(reloaded.ingestionSources())
                    .containsExactlyInAnyOrder(IngestionSource.SMS, IngestionSource.EMAIL);
                assertThat(reloaded.reconciliationStatus()).isEqualTo(ReconciliationStatus.AUTO_MERGED);
            });
    }

    @Test
    void shouldSerializeAndPersistVendorRulesUsingTheUserScopedRuleKey() {
        VendorCategoryRule rule = VendorCategoryRule.fromCorrection(
            "Saira Banu", "Food & Dining", "Tea & Snacks", "Tea Stall"
        );

        Map<String, String> item = DynamoDbItem.fromVendorRule("user-123", rule);
        assertThat(item.get("PK")).isEqualTo("USER#user-123");
        assertThat(item.get("SK")).isEqualTo("RULE#saira banu");
        assertThat(item.get("entityType")).isEqualTo("VENDOR_RULE");

        adapter.save(rule);

        assertThat(adapter.findByPayeeKey("SAIRA BANU!"))
            .hasValueSatisfying(saved -> {
                assertThat(saved.categoryId()).isEqualTo("Food & Dining");
                assertThat(saved.subCategory()).isEqualTo("Tea & Snacks");
            });
    }

    @Test
    void shouldSerializeAndPersistPeerDebtUsingSingleTableKeys() {
        PeerDebtEntry debt = new PeerDebtEntry(
            "debt-999",
            "Alice",
            Money.of("500.00", "INR"),
            "Weekend Trip",
            true,
            false
        );

        Map<String, String> item = DynamoDbItem.fromPeerDebt("user-123", debt);
        assertThat(item.get("PK")).isEqualTo("USER#user-123");
        assertThat(item.get("SK")).isEqualTo("DEBT#Alice#debt-999");
        assertThat(item.get("entityType")).isEqualTo("PEER_DEBT");
        assertThat(item.get("isLent")).isEqualTo("true");
        assertThat(item.get("isSettled")).isEqualTo("false");

        adapter.save(debt);

        PeerDebtEntry retrieved = adapter.findDebtById("debt-999").orElseThrow();
        assertThat(retrieved.contactName()).isEqualTo("Alice");
        assertThat(retrieved.amount()).isEqualTo(Money.of("500.00", "INR"));
        assertThat(retrieved.isLent()).isTrue();
        assertThat(retrieved.isSettled()).isFalse();

        List<PeerDebtEntry> aliceDebts = adapter.findByContactName("Alice");
        assertThat(aliceDebts).hasSize(1);

        List<PeerDebtEntry> unsettled = adapter.findAllUnsettled();
        assertThat(unsettled).hasSize(1);

        debt.settle();
        adapter.save(debt);

        assertThat(adapter.findAllUnsettled()).isEmpty();
        assertThat(adapter.findDebtById("debt-999").get().isSettled()).isTrue();
    }

    @Test
    void shouldSerializeAndPersistLoanAccountUsingSingleTableKeys() {
        LoanAccount loan = new LoanAccount(
            "loan-500",
            "SBI Auto Loan",
            "SBI",
            Money.of("500000.00", "INR"),
            Money.of("12500.00", "INR"),
            8.5,
            48,
            6,
            java.time.LocalDate.of(2026, 9, 10)
        );

        Map<String, String> item = DynamoDbItem.fromLoanAccount("user-123", loan);
        assertThat(item.get("PK")).isEqualTo("USER#user-123");
        assertThat(item.get("SK")).isEqualTo("LOAN#loan-500");
        assertThat(item.get("entityType")).isEqualTo("LOAN");
        assertThat(item.get("lenderName")).isEqualTo("SBI");
        assertThat(item.get("status")).isEqualTo("ACTIVE");

        adapter.save(loan);

        LoanAccount retrieved = adapter.findLoanById("loan-500").orElseThrow();
        assertThat(retrieved.loanName()).isEqualTo("SBI Auto Loan");
        assertThat(retrieved.completedInstallments()).isEqualTo(6);
        assertThat(retrieved.remainingInstallments()).isEqualTo(42);

        List<LoanAccount> active = adapter.findAllActive();
        assertThat(active).hasSize(1);
    }

    @Test
    void shouldSerializeAndPersistCardEmiPlanUsingSingleTableKeys() {
        CardEmiPlan plan = new CardEmiPlan(
            "emi-900",
            "card-hdfc-1234",
            "Apple Store iPhone",
            Money.of("120000.00", "INR"),
            Money.of("10800.00", "INR"),
            14.5,
            12,
            2,
            java.time.LocalDate.of(2026, 9, 25)
        );

        Map<String, String> item = DynamoDbItem.fromCardEmiPlan("user-123", plan);
        assertThat(item.get("PK")).isEqualTo("USER#user-123");
        assertThat(item.get("SK")).isEqualTo("CARD_EMI#card-hdfc-1234#emi-900");
        assertThat(item.get("entityType")).isEqualTo("CARD_EMI");
        assertThat(item.get("merchantName")).isEqualTo("Apple Store iPhone");

        adapter.save(plan);

        CardEmiPlan retrieved = adapter.findEmiPlanById("emi-900").orElseThrow();
        assertThat(retrieved.merchantName()).isEqualTo("Apple Store iPhone");
        assertThat(retrieved.completedInstallments()).isEqualTo(2);
        assertThat(retrieved.remainingInstallments()).isEqualTo(10);

        List<CardEmiPlan> cardPlans = adapter.findActiveByCardId("card-hdfc-1234");
        assertThat(cardPlans).hasSize(1);

        List<CardEmiPlan> allActive = adapter.findAllActiveEmiPlans();
        assertThat(allActive).hasSize(1);
    }

    @Test
    void shouldSerializeAndPersistBillStatementUsingSingleTableKeys() {
        BillStatement bill = new BillStatement(
            "bill-800",
            new AccountId("card-sbi-5678"),
            "SBI Credit Card",
            Money.of("18500.00", "INR"),
            Money.of("1500.00", "INR"),
            java.time.LocalDate.of(2026, 8, 20),
            java.time.LocalDate.of(2026, 9, 10)
        );

        Map<String, String> item = DynamoDbItem.fromBillStatement("user-123", bill);
        assertThat(item.get("PK")).isEqualTo("USER#user-123");
        assertThat(item.get("SK")).isEqualTo("BILL#bill-800");
        assertThat(item.get("entityType")).isEqualTo("BILL");
        assertThat(item.get("cardName")).isEqualTo("SBI Credit Card");
        assertThat(item.get("status")).isEqualTo("PENDING");

        adapter.save(bill);

        BillStatement retrieved = adapter.findBillById("bill-800").orElseThrow();
        assertThat(retrieved.cardName()).isEqualTo("SBI Credit Card");
        assertThat(retrieved.totalAmount()).isEqualTo(Money.of("18500.00", "INR"));
        assertThat(retrieved.status()).isEqualTo(BillStatus.PENDING);

        List<BillStatement> pending = adapter.findPendingBills();
        assertThat(pending).hasSize(1);

        bill.markPaid();
        adapter.save(bill);

        assertThat(adapter.findPendingBills()).isEmpty();
        assertThat(adapter.findBillById("bill-800").get().isPaid()).isTrue();
    }

    @Test
    void shouldPersistAndAtomicallyClaimEachScheduledBillReminder() {
        BillStatement bill = new BillStatement(
            "bill-reminder-800",
            new AccountId("card-sbi-5678"),
            "SBI Credit Card",
            Money.of("18500.00", "INR"),
            Money.of("1500.00", "INR"),
            java.time.LocalDate.of(2026, 8, 20),
            java.time.LocalDate.of(2026, 9, 10)
        );
        BillReminder reminder = BillReminder.scheduledFor(bill, BillReminderTiming.FIVE_DAYS_BEFORE);

        assertThat(adapter.scheduleIfAbsent(reminder)).isTrue();
        assertThat(adapter.scheduleIfAbsent(reminder)).isFalse();
        assertThat(adapter.findScheduledFor(java.time.LocalDate.of(2026, 9, 5))).containsExactly(reminder);
        assertThat(adapter.claim(reminder.id())).contains(reminder.withStatus(BillReminderStatus.CLAIMED));
        assertThat(adapter.claim(reminder.id())).isEmpty();

        adapter.markDelivered(reminder.id());

        assertThat(adapter.findScheduledFor(java.time.LocalDate.of(2026, 9, 5))).isEmpty();
    }

    @Test
    void shouldSerializeAndPersistCategoryBudgetUsingSingleTableKeys() {
        CategoryBudget budget = new CategoryBudget(
            "b-700",
            "CAT_SHOPPING",
            "Shopping & Lifestyle",
            "2026-08",
            Money.of("20000.00", "INR"),
            Money.of("12000.00", "INR")
        );

        Map<String, String> item = DynamoDbItem.fromCategoryBudget("user-123", budget);
        assertThat(item.get("PK")).isEqualTo("USER#user-123");
        assertThat(item.get("SK")).isEqualTo("BUDGET#2026-08#CAT_SHOPPING");
        assertThat(item.get("entityType")).isEqualTo("BUDGET");
        assertThat(item.get("categoryName")).isEqualTo("Shopping & Lifestyle");

        adapter.save(budget);

        CategoryBudget retrieved = adapter.findBudget("CAT_SHOPPING", "2026-08").orElseThrow();
        assertThat(retrieved.categoryName()).isEqualTo("Shopping & Lifestyle");
        assertThat(retrieved.limitAmount()).isEqualTo(Money.of("20000.00", "INR"));
        assertThat(retrieved.currentSpend()).isEqualTo(Money.of("12000.00", "INR"));
        assertThat(retrieved.getSpendPercentage()).isEqualTo(60.0);

        List<CategoryBudget> monthBudgets = adapter.findBudgetsForMonth("2026-08");
        assertThat(monthBudgets).hasSize(1);
    }
}
