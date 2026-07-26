package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.application.port.in.IngestTransactionUseCase;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDateTime;

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
        // Arrange
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

        // Act
        Transaction ingestedTxn = ingestTransactionUseCase.ingestManualTransaction(command);

        // Assert
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
        // Arrange
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

        // Act
        Transaction ingestedTxn = ingestTransactionUseCase.ingestSmsTransaction(smsSender, smsBody, receivedAt);

        // Assert
        assertThat(ingestedTxn).isNotNull();
        assertThat(ingestedTxn.accountId()).isEqualTo(new AccountId("acc-2"));
        assertThat(ingestedTxn.amount().amount()).isEqualByComparingTo("250.00");
        assertThat(ingestedTxn.merchantName()).isEqualTo("Amazon");
        assertThat(ingestedTxn.ingestionSource()).isEqualTo(IngestionSource.SMS);
    }
}
