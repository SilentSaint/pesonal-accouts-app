package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.application.port.in.IngestTransactionUseCase;
import com.automaticexpense.tracker.application.port.in.ReconciliationReviewUseCase;
import com.automaticexpense.tracker.application.port.out.AccountRepository;
import com.automaticexpense.tracker.application.port.out.AccountTransactionRepository;
import com.automaticexpense.tracker.application.port.out.CanonicalTransactionRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.application.port.out.VendorRuleRepository;
import com.automaticexpense.tracker.domain.*;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ConcurrentHashMap;

public class IngestTransactionService implements IngestTransactionUseCase, ReconciliationReviewUseCase {

    private final AccountRepository accountRepository;
    private final TransactionRepository transactionRepository;
    private final AccountTransactionRepository atomicRepository;
    private final CanonicalTransactionRepository canonicalRepository;
    private final SmsTransactionParser smsParser;
    private final EmailTransactionParser emailParser;
    private final DeduplicationEngine deduplicationEngine;
    private final AccountDiscoveryEngine discoveryEngine;
    private final VendorRuleRepository vendorRules;
    private final VendorRuleLearningService vendorRuleLearningService;
    private final Map<String, EmailAccountConfig> linkedEmailAccounts = new ConcurrentHashMap<>();

    public IngestTransactionService(
        AccountRepository accountRepository,
        TransactionRepository transactionRepository,
        VendorRuleRepository vendorRules
    ) {
        this.accountRepository = Objects.requireNonNull(accountRepository, "accountRepository cannot be null");
        this.transactionRepository = Objects.requireNonNull(transactionRepository, "transactionRepository cannot be null");
        this.atomicRepository = null;
        this.canonicalRepository = transactionRepository instanceof CanonicalTransactionRepository repository
            ? repository : null;
        this.vendorRules = Objects.requireNonNull(vendorRules, "vendorRules cannot be null");
        this.vendorRuleLearningService = new VendorRuleLearningService(transactionRepository, vendorRules);
        this.smsParser = new SmsTransactionParser();
        this.emailParser = new EmailTransactionParser();
        this.deduplicationEngine = new DeduplicationEngine();
        this.discoveryEngine = new AccountDiscoveryEngine();
    }

    public IngestTransactionService(AccountTransactionRepository repository, VendorRuleRepository vendorRules) {
        this.accountRepository = Objects.requireNonNull(repository, "repository cannot be null");
        this.transactionRepository = repository;
        this.atomicRepository = repository;
        this.canonicalRepository = repository instanceof CanonicalTransactionRepository canonical
            ? canonical : null;
        this.vendorRules = Objects.requireNonNull(vendorRules, "vendorRules cannot be null");
        this.vendorRuleLearningService = new VendorRuleLearningService(repository, vendorRules);
        this.smsParser = new SmsTransactionParser();
        this.emailParser = new EmailTransactionParser();
        this.deduplicationEngine = new DeduplicationEngine();
        this.discoveryEngine = new AccountDiscoveryEngine();
    }

    @Override
    public Transaction ingestManualTransaction(IngestTransactionCommand command) {
        return ingestManualTransaction(
            command,
            new TransactionId("txn-" + System.currentTimeMillis() + "-" + (int) (Math.random() * 1000))
        );
    }

    @Override
    public Transaction ingestManualTransaction(
        IngestTransactionCommand command,
        TransactionId commandId
    ) {
        FinancialAccount account = accountRepository.findById(command.accountId())
            .orElseThrow(() -> new IllegalArgumentException("Account not found with ID: " + command.accountId().value()));

        account.applyTransaction(command.amount(), command.type());

        Transaction transaction = new Transaction(
            commandId,
            command.amount(),
            command.type(),
            command.timestamp(),
            command.merchantName(),
            command.accountId(),
            command.categoryId(),
            command.subCategory(),
            command.ingestionSource(),
            ReconciliationStatus.CONFIRMED,
            command.netPersonalExpense(),
            command.accountMask(),
            command.referenceNumber(),
            command.rawSnippet(),
            command.transferCounterpartMask()
        );

        if (atomicRepository != null) {
            if (atomicRepository.saveAtomically(account, transaction)) {
                return transaction;
            }
            return transactionRepository.findById(commandId)
                .orElseThrow(() -> new IllegalStateException("Duplicate command did not persist a transaction"));
        }

        accountRepository.save(account);
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
            Transaction merged = existing.enrichedWith(source);
            transactionRepository.save(merged);
            return merged;
        }

        Money amount = new Money(parsed.amount(), parsed.currency());
        ReconciliationStatus status = dedupResult.recommendedStatus();

        VendorCategoryRule matchingRule = findMatchingRule(parsed.merchantName());
        String learnedCategory = matchingRule == null ? null : matchingRule.categoryId();
        String learnedSubCategory = matchingRule == null ? null : matchingRule.subCategory();
        if (matchingRule == null && status == ReconciliationStatus.CONFIRMED) {
            status = ReconciliationStatus.NEEDS_REVIEW;
        }

        Transaction transaction = new Transaction(
            new TransactionId(idPrefix + System.currentTimeMillis() + "-" + (int)(Math.random() * 1000)),
            amount,
            parsed.type(),
            parsed.timestamp(),
            parsed.merchantName(),
            account.id(),
            learnedCategory,
            learnedSubCategory,
            source,
            status,
            amount,
            null,
            null,
            null,
            null
        );

        if (dedupResult.action() == DeduplicationAction.FLAG_NEEDS_REVIEW) {
            transaction = transaction.withPotentialDuplicateOf(dedupResult.matchingTransactionId());
        } else {
            account.applyTransaction(amount, parsed.type());
            accountRepository.save(account);
        }
        transactionRepository.save(transaction);
        return transaction;
    }

    @Override
    public List<Transaction> getPendingReviewTransactions() {
        return transactionRepository.findByReconciliationStatus(ReconciliationStatus.NEEDS_REVIEW);
    }

    @Override
    public List<ReconciliationReview> getPendingReconciliationReviews() {
        return getPendingReviewTransactions().stream()
            .map(candidate -> new ReconciliationReview(
                candidate,
                candidate.potentialDuplicateOfTransactionId() == null
                    ? null
                    : transactionRepository.findById(candidate.potentialDuplicateOfTransactionId()).orElse(null)
            ))
            .toList();
    }

    @Override
    public Transaction confirmTransaction(TransactionId id, String categoryId) {
        Transaction existing = transactionRepository.findById(id)
            .orElseThrow(() -> new IllegalArgumentException("Transaction not found: " + id.value()));

        Transaction confirmed = existing.confirmedAsSeparate(categoryId);
        if (existing.potentialDuplicateOfTransactionId() != null) {
            FinancialAccount account = accountRepository.findById(existing.accountId())
                .orElseThrow(() -> new IllegalStateException("Account not found: " + existing.accountId().value()));
            account.applyTransaction(existing.amount(), existing.type());
            if (canonicalRepository != null) {
                if (!canonicalRepository.confirmAsSeparate(account, confirmed)) {
                    return transactionRepository.findById(id)
                        .filter(transaction -> transaction.reconciliationStatus() == ReconciliationStatus.CONFIRMED)
                        .orElseThrow(() -> new IllegalStateException("Review confirmation was not persisted"));
                }
            } else {
                accountRepository.save(account);
                transactionRepository.save(confirmed);
            }
        } else {
            transactionRepository.save(confirmed);
        }
        return confirmed;
    }

    @Override
    public Transaction assignCategoryAndLearnRule(
        TransactionId id,
        String categoryId,
        String subCategory,
        String payeeNickname
    ) {
        return vendorRuleLearningService.learn(id, categoryId, subCategory, payeeNickname);
    }

    @Override
    public Transaction mergeTransactions(TransactionId targetId, TransactionId duplicateId) {
        Transaction target = transactionRepository.findById(targetId)
            .orElseThrow(() -> new IllegalArgumentException("Target transaction not found: " + targetId.value()));
        Transaction duplicate = transactionRepository.findById(duplicateId)
            .orElseThrow(() -> new IllegalArgumentException("Duplicate transaction not found: " + duplicateId.value()));

        if (duplicate.potentialDuplicateOfTransactionId() != null
            && !target.id().equals(duplicate.potentialDuplicateOfTransactionId())) {
            throw new IllegalArgumentException("Duplicate is not assigned to the supplied canonical transaction");
        }
        Transaction merged = target.enrichedWith(duplicate.ingestionSource());
        if (canonicalRepository != null) {
            if (!canonicalRepository.mergeCanonically(merged, duplicate)) {
                return transactionRepository.findById(targetId)
                    .filter(transaction -> transaction.ingestionSources().contains(duplicate.ingestionSource()))
                    .orElseThrow(() -> new IllegalStateException("Duplicate merge was not persisted"));
            }
        } else {
            transactionRepository.delete(duplicate.id());
            transactionRepository.save(merged);
        }
        return merged;
    }

    @Override
    public BackfillResult execute30DayBackfill(List<String> smsBodies, List<String> emailBodies) {
        List<ParsedTransactionEvent> smsEvents = new ArrayList<>();
        if (smsBodies != null) {
            LocalDateTime now = LocalDateTime.now();
            for (String body : smsBodies) {
                ParsedTransactionEvent event = smsParser.parse("UNKNOWN", body, now.minusDays((int)(Math.random() * 25)));
                if (event != null) smsEvents.add(event);
            }
        }

        List<ParsedTransactionEvent> emailEvents = new ArrayList<>();
        if (emailBodies != null) {
            LocalDateTime now = LocalDateTime.now();
            for (String body : emailBodies) {
                ParsedTransactionEvent event = emailParser.parse("UNKNOWN", "Transaction Alert", body, now.minusDays((int)(Math.random() * 25)));
                if (event != null) emailEvents.add(event);
            }
        }

        BackfillResult result = discoveryEngine.processHistoricalEvents(smsEvents, emailEvents, new ArrayList<>());

        for (FinancialAccount acc : result.discoveredAccounts()) {
            accountRepository.save(acc);
        }

        for (Transaction txn : result.transactions()) {
            transactionRepository.save(txn);
        }

        return result;
    }

    @Override
    public EmailAccountConfig linkEmailAccount(String emailAddress) {
        if (emailAddress == null || !emailAddress.contains("@")) {
            throw new IllegalArgumentException("Invalid email address");
        }
        EmailAccountConfig config = new EmailAccountConfig(emailAddress, "PUSH_ACTIVE", LocalDateTime.now());
        linkedEmailAccounts.put(emailAddress.toLowerCase(), config);
        return config;
    }

    @Override
    public List<EmailAccountConfig> getLinkedEmailAccounts() {
        return new ArrayList<>(linkedEmailAccounts.values());
    }

    private VendorCategoryRule findMatchingRule(String merchantName) {
        String normalizedPayee = VendorCategoryRule.normalizePayeeKey(merchantName);
        return vendorRules.findByPayeeKey(normalizedPayee)
            .or(() -> vendorRules.findAll().stream()
                .filter(rule -> rule.matches(merchantName))
                .max(java.util.Comparator.comparingInt(rule -> rule.payeeKey().length())))
            .orElse(null);
    }
}
