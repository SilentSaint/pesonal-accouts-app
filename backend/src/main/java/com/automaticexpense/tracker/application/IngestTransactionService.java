package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.application.port.in.IngestTransactionUseCase;
import com.automaticexpense.tracker.application.port.out.AccountRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.*;

import java.time.LocalDateTime;
import java.util.Objects;

public class IngestTransactionService implements IngestTransactionUseCase {

    private final AccountRepository accountRepository;
    private final TransactionRepository transactionRepository;
    private final SmsTransactionParser smsParser;

    public IngestTransactionService(AccountRepository accountRepository, TransactionRepository transactionRepository) {
        this.accountRepository = Objects.requireNonNull(accountRepository, "accountRepository cannot be null");
        this.transactionRepository = Objects.requireNonNull(transactionRepository, "transactionRepository cannot be null");
        this.smsParser = new SmsTransactionParser();
    }

    @Override
    public Transaction ingestManualTransaction(IngestTransactionCommand command) {
        FinancialAccount account = accountRepository.findById(command.accountId())
            .orElseThrow(() -> new IllegalArgumentException("Account not found with ID: " + command.accountId().value()));

        account.applyTransaction(command.amount(), command.type());
        accountRepository.save(account);

        Transaction transaction = new Transaction(
            new TransactionId("txn-" + System.currentTimeMillis() + "-" + (int)(Math.random() * 1000)),
            command.amount(),
            command.type(),
            command.timestamp(),
            command.merchantName(),
            command.accountId(),
            command.categoryId(),
            command.ingestionSource(),
            ReconciliationStatus.CONFIRMED,
            command.amount()
        );

        transactionRepository.save(transaction);
        return transaction;
    }

    @Override
    public Transaction ingestSmsTransaction(String sender, String body, LocalDateTime receivedAt) {
        ParsedTransactionEvent parsed = smsParser.parse(sender, body, receivedAt);
        if (parsed == null) {
            throw new IllegalArgumentException("Failed to parse SMS transaction body");
        }

        FinancialAccount account = accountRepository.findByLastFourDigits(parsed.accountLast4())
            .orElseGet(() -> {
                FinancialAccount defaultAcc = new FinancialAccount(
                    new AccountId("acc-auto-" + parsed.accountLast4()),
                    "Auto Account " + parsed.accountLast4(),
                    AccountType.SAVINGS,
                    parsed.accountLast4(),
                    parsed.currency(),
                    new Money(java.math.BigDecimal.ZERO, parsed.currency())
                );
                accountRepository.save(defaultAcc);
                return defaultAcc;
            });

        Money amount = new Money(parsed.amount(), parsed.currency());
        account.applyTransaction(amount, parsed.type());
        accountRepository.save(account);

        Transaction transaction = new Transaction(
            new TransactionId("txn-sms-" + System.currentTimeMillis()),
            amount,
            parsed.type(),
            parsed.timestamp(),
            parsed.merchantName(),
            account.id(),
            null,
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            amount
        );

        transactionRepository.save(transaction);
        return transaction;
    }
}
