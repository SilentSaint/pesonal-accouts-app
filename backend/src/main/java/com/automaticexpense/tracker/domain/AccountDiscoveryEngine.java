package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.util.*;

public class AccountDiscoveryEngine {

    private final DeduplicationEngine deduplicationEngine = new DeduplicationEngine();

    public BackfillResult processHistoricalEvents(
        List<ParsedTransactionEvent> smsEvents,
        List<ParsedTransactionEvent> emailEvents,
        List<FinancialAccount> existingAccounts
    ) {
        Map<String, FinancialAccount> accountMap = new HashMap<>();
        if (existingAccounts != null) {
            for (FinancialAccount acc : existingAccounts) {
                accountMap.put(acc.lastFourDigits(), acc);
            }
        }

        List<ParsedTransactionEvent> allEvents = new ArrayList<>();
        if (smsEvents != null) allEvents.addAll(smsEvents);
        if (emailEvents != null) allEvents.addAll(emailEvents);

        // Sort events chronologically
        allEvents.sort(Comparator.comparing(ParsedTransactionEvent::timestamp));

        List<Transaction> createdTransactions = new ArrayList<>();
        int autoMergedCount = 0;

        for (ParsedTransactionEvent event : allEvents) {
            String last4 = event.accountLast4();
            FinancialAccount account = accountMap.computeIfAbsent(last4, k -> new FinancialAccount(
                new AccountId("acc-auto-" + k),
                "Discovered Account " + k,
                AccountType.SAVINGS,
                k,
                event.currency(),
                new Money(BigDecimal.ZERO, event.currency())
            ));

            DeduplicationResult dedupResult = deduplicationEngine.evaluate(
                event,
                IngestionSource.SMS,
                createdTransactions.stream()
                    .filter(t -> t.accountId().equals(account.id()))
                    .toList()
            );

            if (dedupResult.action() == DeduplicationAction.AUTO_MERGE) {
                autoMergedCount++;
                Transaction existing = createdTransactions.stream()
                    .filter(t -> t.id().equals(dedupResult.matchingTransactionId()))
                    .findFirst()
                    .orElse(null);

                if (existing != null) {
                    createdTransactions.remove(existing);
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
                    createdTransactions.add(merged);
                }
            } else {
                Money amount = new Money(event.amount(), event.currency());
                account.applyTransaction(amount, event.type());

                Transaction txn = new Transaction(
                    new TransactionId("txn-backfill-" + System.nanoTime()),
                    amount,
                    event.type(),
                    event.timestamp(),
                    event.merchantName(),
                    account.id(),
                    null,
                    IngestionSource.SMS,
                    dedupResult.recommendedStatus(),
                    amount
                );
                createdTransactions.add(txn);
            }
        }

        return new BackfillResult(
            new ArrayList<>(accountMap.values()),
            createdTransactions,
            allEvents.size(),
            autoMergedCount
        );
    }
}
