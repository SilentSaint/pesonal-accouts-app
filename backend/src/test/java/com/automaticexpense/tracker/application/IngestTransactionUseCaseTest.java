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
    private IngestTransactionUseCase ingestTransactionUseCase;

    @BeforeEach
    void setUp() {
        accountRepository = new InMemoryAccountRepository();
        transactionRepository = new InMemoryTransactionRepository();
        ingestTransactionUseCase = new IngestTransactionService(accountRepository, transactionRepository);
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

        // 1. Ingest SMS
        String smsBody = "INR 850.00 spent on Card 1234 at Swiggy on 2026-07-26.";
        Transaction smsTxn = ingestTransactionUseCase.ingestSmsTransaction("HDFCBK", smsBody, baseTime);

        // 2. Ingest Email 8 minutes later (within +-15m window) for same card, amount, and merchant
        String emailSubject = "Order Confirmation: Swiggy";
        String emailBody = "INR 850.00 debited from card ending in 1234 at Swiggy on 2026-07-26.";
        Transaction emailTxn = ingestTransactionUseCase.ingestEmailTransaction("alerts@swiggy.in", emailSubject, emailBody, baseTime.plusMinutes(8));

        assertThat(emailTxn.id()).isEqualTo(smsTxn.id());
        assertThat(emailTxn.reconciliationStatus()).isEqualTo(ReconciliationStatus.AUTO_MERGED);
    }

    @Test
    void shouldFlagAmbiguousDualChannelEventAsNeedsReview() {
        FinancialAccount account = new FinancialAccount(
            new AccountId("acc-4"),
            "ICICI Savings Account",
            AccountType.SAVINGS,
            "9988",
            "INR",
            new Money(new BigDecimal("5000.00"), "INR")
        );
        accountRepository.save(account);

        LocalDateTime baseTime = LocalDateTime.of(2026, 7, 26, 15, 0);

        // 1. Ingest SMS with merchant string "Bundl Tech"
        String smsBody = "Rs 499.00 debited from a/c **9988 at Bundl Tech.";
        Transaction smsTxn = ingestTransactionUseCase.ingestSmsTransaction("ICICIB", smsBody, baseTime);

        // 2. Ingest Email with merchant string "Swiggy Pay" (ambiguous matching merchant)
        String emailSubject = "Transaction Alert";
        String emailBody = "INR 499.00 debited from account 9988 at Swiggy Pay.";
        Transaction emailTxn = ingestTransactionUseCase.ingestEmailTransaction("alerts@icici.com", emailSubject, emailBody, baseTime.plusMinutes(5));

        assertThat(emailTxn.reconciliationStatus()).isEqualTo(ReconciliationStatus.NEEDS_REVIEW);

        List<Transaction> pendingReviews = ingestTransactionUseCase.getPendingReviewTransactions();
        assertThat(pendingReviews).isNotEmpty();
    }

    @Test
    void shouldAllow1TapConfirmOrMergeForPendingReviewTransactions() {
        FinancialAccount account = new FinancialAccount(
            new AccountId("acc-5"),
            "Axis Bank Account",
            AccountType.SAVINGS,
            "1122",
            "INR",
            new Money(new BigDecimal("1000.00"), "INR")
        );
        accountRepository.save(account);

        LocalDateTime baseTime = LocalDateTime.of(2026, 7, 26, 16, 0);

        String smsBody = "Rs 300.00 debited from a/c **1122 at Cafe Coffee Day.";
        Transaction smsTxn = ingestTransactionUseCase.ingestSmsTransaction("AXISBK", smsBody, baseTime);

        String emailSubject = "Alert: Axis Bank";
        String emailBody = "INR 300.00 debited from account 1122 at CCD.";
        Transaction emailTxn = ingestTransactionUseCase.ingestEmailTransaction("alerts@axisbank.com", emailSubject, emailBody, baseTime.plusMinutes(2));

        // 1-Tap Confirm
        Transaction confirmed = ingestTransactionUseCase.confirmTransaction(emailTxn.id(), "Food & Dining");
        assertThat(confirmed.reconciliationStatus()).isEqualTo(ReconciliationStatus.CONFIRMED);
        assertThat(confirmed.categoryId()).isEqualTo("Food & Dining");

        // 1-Tap Merge
        Transaction merged = ingestTransactionUseCase.mergeTransactions(smsTxn.id(), emailTxn.id());
        assertThat(merged.reconciliationStatus()).isEqualTo(ReconciliationStatus.AUTO_MERGED);
        assertThat(transactionRepository.findById(emailTxn.id())).isEmpty();
    }
}
