package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.application.port.in.IngestTransactionUseCase;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class IngestTransactionUseCaseTest {

    private InMemoryAccountRepository accountRepository;
    private InMemoryTransactionRepository transactionRepository;
    private InMemoryVendorRuleRepository vendorRuleRepository;
    private IngestTransactionUseCase ingestTransactionUseCase;

    @BeforeEach
    void setUp() {
        accountRepository = new InMemoryAccountRepository();
        transactionRepository = new InMemoryTransactionRepository();
        vendorRuleRepository = new InMemoryVendorRuleRepository();
        ingestTransactionUseCase = new IngestTransactionService(
            accountRepository, transactionRepository, vendorRuleRepository
        );
    }

    @Test
    void shouldIngestManualDebitTransactionAndUpdateAccountBalance() {
        FinancialAccount account = new FinancialAccount(
            new AccountId("acc-1"),
            "HDFC Salary Account",
            AccountType.SAVINGS,
            "1234",
            "INR",
            new Money(new BigDecimal("10000.00"), "INR")
        );
        accountRepository.save(account);

        IngestTransactionCommand command = new IngestTransactionCommand(
            new Money(new BigDecimal("500.00"), "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 7, 26, 10, 0),
            "Starbucks",
            new AccountId("acc-1"),
            null,
            IngestionSource.MANUAL
        );

        Transaction ingestedTxn = ingestTransactionUseCase.ingestManualTransaction(command);

        assertThat(ingestedTxn).isNotNull();
        assertThat(ingestedTxn.id()).isNotNull();
        assertThat(ingestedTxn.amount().amount()).isEqualByComparingTo("500.00");
        assertThat(ingestedTxn.merchantName()).isEqualTo("Starbucks");
        assertThat(ingestedTxn.reconciliationStatus()).isEqualTo(ReconciliationStatus.CONFIRMED);

        FinancialAccount updatedAccount = accountRepository.findById(new AccountId("acc-1")).orElseThrow();
        assertThat(updatedAccount.currentBalance().amount()).isEqualByComparingTo("9500.00");
    }

    @Test
    void shouldPersistEveryEditedReviewFieldOnManualConfirmation() {
        accountRepository.save(new FinancialAccount(
            new AccountId("acc-1234"),
            "Review account",
            AccountType.SAVINGS,
            "1234",
            "INR",
            Money.of("10000.00", "INR")
        ));
        IngestTransactionCommand command = new IngestTransactionCommand(
            Money.of("913.42", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 8, 29, 6, 0),
            "Green Market",
            new AccountId("acc-1234"),
            "Groceries",
            IngestionSource.MANUAL,
            "Fruits & Vegetables",
            Money.of("900.00", "INR"),
            "•••• 1234",
            "upi-12345678",
            "edited receipt",
            "•••• 9876"
        );

        Transaction confirmed = ingestTransactionUseCase.ingestManualTransaction(command);

        assertThat(confirmed.merchantName()).isEqualTo("Green Market");
        assertThat(confirmed.amount()).isEqualTo(Money.of("913.42", "INR"));
        assertThat(confirmed.type()).isEqualTo(TransactionType.DEBIT);
        assertThat(confirmed.timestamp()).isEqualTo(LocalDateTime.of(2026, 8, 29, 6, 0));
        assertThat(confirmed.accountId()).isEqualTo(new AccountId("acc-1234"));
        assertThat(confirmed.categoryId()).isEqualTo("Groceries");
        assertThat(confirmed.subCategory()).isEqualTo("Fruits & Vegetables");
        assertThat(confirmed.ingestionSource()).isEqualTo(IngestionSource.MANUAL);
        assertThat(confirmed.reconciliationStatus()).isEqualTo(ReconciliationStatus.CONFIRMED);
        assertThat(confirmed.netPersonalExpense()).isEqualTo(Money.of("900.00", "INR"));
        assertThat(confirmed.accountMask()).isEqualTo("•••• 1234");
        assertThat(confirmed.referenceNumber()).isEqualTo("upi-12345678");
        assertThat(confirmed.rawSnippet()).isEqualTo("edited receipt");
        assertThat(confirmed.transferCounterpartMask()).isEqualTo("•••• 9876");
    }

    @Test
    void shouldIngestSmsTransactionAndMatchAccountByLastFourDigits() {
        FinancialAccount account = new FinancialAccount(
            new AccountId("acc-2"),
            "SBI Credit Card",
            AccountType.CREDIT_CARD,
            "5678",
            "INR",
            new Money(new BigDecimal("0.00"), "INR")
        );
        accountRepository.save(account);

        String smsSender = "VK-HDFCBK";
        String smsBody = "Rs. 250.00 spent on A/C **5678 at Amazon on 2026-07-26.";
        LocalDateTime receivedAt = LocalDateTime.of(2026, 7, 26, 12, 30);

        Transaction ingestedTxn = ingestTransactionUseCase.ingestSmsTransaction(smsSender, smsBody, receivedAt);

        assertThat(ingestedTxn).isNotNull();
        assertThat(ingestedTxn.accountId()).isEqualTo(new AccountId("acc-2"));
        assertThat(ingestedTxn.amount().amount()).isEqualByComparingTo("250.00");
        assertThat(ingestedTxn.merchantName()).isEqualTo("Amazon");
        assertThat(ingestedTxn.ingestionSource()).isEqualTo(IngestionSource.SMS);
    }

    @Test
    void shouldIngestEmailTransactionAndAutoDeduplicateWithSmsWithin15Minutes() {
        FinancialAccount account = new FinancialAccount(
            new AccountId("acc-3"),
            "HDFC Credit Card",
            AccountType.CREDIT_CARD,
            "1234",
            "INR",
            new Money(new BigDecimal("0.00"), "INR")
        );
        accountRepository.save(account);

        LocalDateTime baseTime = LocalDateTime.of(2026, 7, 26, 14, 0);

        String smsBody = "INR 850.00 spent on Card 1234 at Swiggy on 2026-07-26.";
        Transaction smsTxn = ingestTransactionUseCase.ingestSmsTransaction("HDFCBK", smsBody, baseTime);

        String emailSubject = "Order Confirmation: Swiggy";
        String emailBody = "INR 850.00 debited from card ending in 1234 at Swiggy on 2026-07-26.";
        Transaction emailTxn = ingestTransactionUseCase.ingestEmailTransaction("alerts@swiggy.in", emailSubject, emailBody, baseTime.plusMinutes(8));

        assertThat(emailTxn.id()).isEqualTo(smsTxn.id());
        assertThat(emailTxn.reconciliationStatus()).isEqualTo(ReconciliationStatus.AUTO_MERGED);
        assertThat(emailTxn.ingestionSources())
            .containsExactlyInAnyOrder(IngestionSource.SMS, IngestionSource.EMAIL);
        assertThat(transactionRepository.findAllTransactions()).hasSize(1);
        assertThat(accountRepository.findById(account.id()).orElseThrow().currentBalance())
            .isEqualTo(Money.of("-850.00", "INR"));

        Transaction retriedEmail = ingestTransactionUseCase.ingestEmailTransaction(
            "alerts@swiggy.in", emailSubject, emailBody, baseTime.plusMinutes(8)
        );
        assertThat(retriedEmail.id()).isEqualTo(smsTxn.id());
        assertThat(transactionRepository.findAllTransactions()).hasSize(1);
    }

    @Test
    void keepsAnAmbiguousEmailOutOfTheBalanceUntilTheUserMergesIt() {
        FinancialAccount account = new FinancialAccount(
            new AccountId("acc-ambiguity"),
            "HDFC Credit Card",
            AccountType.CREDIT_CARD,
            "1234",
            "INR",
            Money.of("0.00", "INR")
        );
        accountRepository.save(account);
        LocalDateTime baseTime = LocalDateTime.of(2026, 7, 26, 14, 0);

        Transaction sms = ingestTransactionUseCase.ingestSmsTransaction(
            "HDFCBK",
            "INR 850.00 spent on Card 1234 at Bundl Tech on 2026-07-26.",
            baseTime
        );
        Transaction email = ingestTransactionUseCase.ingestEmailTransaction(
            "alerts@swiggy.in",
            "Payment confirmation",
            "INR 850.00 debited from card ending in 1234 at Swiggy Pay on 2026-07-26.",
            baseTime.plusMinutes(8)
        );

        assertThat(email.reconciliationStatus()).isEqualTo(ReconciliationStatus.NEEDS_REVIEW);
        assertThat(email.potentialDuplicateOfTransactionId()).isEqualTo(sms.id());
        assertThat(accountRepository.findById(account.id()).orElseThrow().currentBalance())
            .isEqualTo(Money.of("-850.00", "INR"));

        Transaction canonical = ingestTransactionUseCase.mergeTransactions(sms.id(), email.id());

        assertThat(canonical.ingestionSources())
            .containsExactlyInAnyOrder(IngestionSource.SMS, IngestionSource.EMAIL);
        assertThat(transactionRepository.findById(email.id())).isEmpty();
        assertThat(ingestTransactionUseCase.getPendingReviewTransactions()).isEmpty();
        assertThat(accountRepository.findById(account.id()).orElseThrow().currentBalance())
            .isEqualTo(Money.of("-850.00", "INR"));
    }

    @Test
    void shouldLearnVendorCategoryRuleAndAutoCategorizeFutureTransactions() {
        FinancialAccount account = new FinancialAccount(
            new AccountId("acc-rule-1"),
            "HDFC Account",
            AccountType.SAVINGS,
            "7788",
            "INR",
            new Money(new BigDecimal("5000.00"), "INR")
        );
        accountRepository.save(account);

        LocalDateTime baseTime = LocalDateTime.of(2026, 7, 26, 10, 0);

        String smsBody1 = "Rs 150.00 debited from a/c **7788 at Saira Banu.";
        Transaction txn1 = ingestTransactionUseCase.ingestSmsTransaction("HDFCBK", smsBody1, baseTime);
        assertThat(txn1.categoryId()).isNull();

        ingestTransactionUseCase.assignCategoryAndLearnRule(
            txn1.id(), "Food & Dining", "Tea & Snacks", "Tea Stall"
        );

        IngestTransactionUseCase restartedUseCase = new IngestTransactionService(
            accountRepository, transactionRepository, vendorRuleRepository
        );
        String smsBody2 = "Rs 200.00 debited from a/c **7788 at Saira Banu Info: UPI.";
        Transaction txn2 = restartedUseCase.ingestSmsTransaction("HDFCBK", smsBody2, baseTime.plusDays(1));

        assertThat(txn2.categoryId()).isEqualTo("Food & Dining");
        assertThat(txn2.subCategory()).isEqualTo("Tea & Snacks");
    }

    @Test
    void leavesAnUnmappedPayeeInTheReviewQueue() {
        accountRepository.save(new FinancialAccount(
            new AccountId("acc-rule-2"),
            "HDFC Account",
            AccountType.SAVINGS,
            "7788",
            "INR",
            Money.of("5000.00", "INR")
        ));

        Transaction transaction = ingestTransactionUseCase.ingestSmsTransaction(
            "HDFCBK",
            "Rs 150.00 debited from a/c **7788 at Unknown Tea Counter.",
            LocalDateTime.of(2026, 7, 26, 10, 0)
        );

        assertThat(transaction.categoryId()).isNull();
        assertThat(transaction.reconciliationStatus()).isEqualTo(ReconciliationStatus.NEEDS_REVIEW);
        assertThat(ingestTransactionUseCase.getPendingReviewTransactions())
            .extracting(Transaction::id)
            .contains(transaction.id());
    }

    @Test
    void shouldExecute30DayHistoricalBackfillAndDiscoverAccounts() {
        List<String> smsBodies = List.of(
            "Rs 450.00 debited from a/c **1122 at Starbucks.",
            "INR 1200.00 spent on Card 3344 at Amazon."
        );
        List<String> emailBodies = List.of(
            "INR 1200.00 debited from card ending in 3344 at Amazon."
        );

        BackfillResult result = ingestTransactionUseCase.execute30DayBackfill(smsBodies, emailBodies);

        assertThat(result.discoveredAccounts()).hasSize(2);
        assertThat(result.transactions()).isNotEmpty();
    }

    @Test
    void shouldLinkEmailAccountSuccessfully() {
        EmailAccountConfig config = ingestTransactionUseCase.linkEmailAccount("user@gmail.com");

        assertThat(config.emailAddress()).isEqualTo("user@gmail.com");
        assertThat(config.status()).isEqualTo("PUSH_ACTIVE");

        List<EmailAccountConfig> linked = ingestTransactionUseCase.getLinkedEmailAccounts();
        assertThat(linked).hasSize(1);
        assertThat(linked.get(0).emailAddress()).isEqualTo("user@gmail.com");
    }
}
