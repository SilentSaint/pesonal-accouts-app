package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.application.port.in.IngestTransactionUseCase;
import com.automaticexpense.tracker.application.port.out.AccountRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Objects;

public class IngestTransactionService implements IngestTransactionUseCase {

    private final AccountRepository accountRepository;
    private final TransactionRepository transactionRepository;
    private final SmsTransactionParser smsParser;
    private final EmailTransactionParser emailParser;
    private final DeduplicationEngine deduplicationEngine;

    public IngestTransactionService(AccountRepository accountRepository, TransactionRepository transactionRepository) {
        this.accountRepository = Objects.requireNonNull(accountRepository, "accountRepository cannot be null");
        this.transactionRepository = Objects.requireNonNull(transactionRepository, "transactionRepository cannot be null");
        this.smsParser = new SmsTransactionParser();
        this.emailParser = new EmailTransactionParser();
        this.deduplicationEngine = new DeduplicationEngine();
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
        return processIngestedEvent(parsed, IngestionSource.SMS, "txn-sms-");
    }

    @Override
    public Transaction ingestEmailTransaction(String sender, String subject, String body, LocalDateTime receivedAt) {
        ParsedTransactionEvent parsed = emailParser.parse(sender, subject, body, receivedAt);
        if (parsed == null) {
            throw new IllegalArgumentException("Failed to parse Email transaction body");
        }
        return processIngestedEvent(parsed, IngestionSource.EMAIL, "txn-email-");
    }

    private Transaction processIngestedEvent(ParsedTransactionEvent parsed, IngestionSource source, String idPrefix) {
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

        List<Transaction> windowTxns = transactionRepository.findByAccountIdAndWindow(
            account.id(),
            parsed.timestamp().minusMinutes(15),
            parsed.timestamp().plusMinutes(15)
        );

        DeduplicationResult dedupResult = deduplicationEngine.evaluate(parsed, source, windowTxns);

        if (dedupResult.action() == DeduplicationAction.AUTO_MERGE) {
            Transaction existing = transactionRepository.findById(dedupResult.matchingTransactionId()).orElseThrow();
            Transaction merged = new Transaction(
                existing.id(),
                existing.amount(),
                existing.type(),
                existing.timestamp(),
                existing.merchantName(),
                existing.accountId(),
                existing.categoryId(),
                existing.ingestionSource(),
                ReconciliationStatus.AUTO_MERGED,
                existing.netPersonalExpense()
            );
            transactionRepository.save(merged);
            return merged;
        }

        Money amount = new Money(parsed.amount(), parsed.currency());
        account.applyTransaction(amount, parsed.type());
        accountRepository.save(account);

        ReconciliationStatus status = dedupResult.recommendedStatus();

        Transaction transaction = new Transaction(
            new TransactionId(idPrefix + System.currentTimeMillis() + "-" + (int)(Math.random() * 1000)),
            amount,
            parsed.type(),
            parsed.timestamp(),
            parsed.merchantName(),
            account.id(),
            null,
            source,
            status,
            amount
        );

        transactionRepository.save(transaction);
        return transaction;
    }

    @Override
    public List<Transaction> getPendingReviewTransactions() {
        return transactionRepository.findByReconciliationStatus(ReconciliationStatus.NEEDS_REVIEW);
    }

    @Override
    public Transaction confirmTransaction(TransactionId id, String categoryId) {
        Transaction existing = transactionRepository.findById(id)
            .orElseThrow(() -> new IllegalArgumentException("Transaction not found: " + id.value()));

        Transaction confirmed = new Transaction(
            existing.id(),
            existing.amount(),
            existing.type(),
            existing.timestamp(),
            existing.merchantName(),
            existing.accountId(),
            categoryId,
            existing.ingestionSource(),
            ReconciliationStatus.CONFIRMED,
            existing.netPersonalExpense()
        );

        transactionRepository.save(confirmed);
        return confirmed;
    }

    @Override
    public Transaction mergeTransactions(TransactionId targetId, TransactionId duplicateId) {
        Transaction target = transactionRepository.findById(targetId)
            .orElseThrow(() -> new IllegalArgumentException("Target transaction not found: " + targetId.value()));
        Transaction duplicate = transactionRepository.findById(duplicateId)
            .orElseThrow(() -> new IllegalArgumentException("Duplicate transaction not found: " + duplicateId.value()));

        Transaction merged = new Transaction(
            target.id(),
            target.amount(),
            target.type(),
            target.timestamp(),
            target.merchantName(),
            target.accountId(),
            target.categoryId(),
            target.ingestionSource(),
            ReconciliationStatus.AUTO_MERGED,
            target.netPersonalExpense()
        );

        transactionRepository.delete(duplicate.id());
        transactionRepository.save(merged);
        return merged;
    }
}
