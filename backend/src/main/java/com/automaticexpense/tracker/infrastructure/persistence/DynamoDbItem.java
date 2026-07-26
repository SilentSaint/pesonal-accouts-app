package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

public class DynamoDbItem {

    public static Map<String, String> fromAccount(String userId, FinancialAccount account) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "ACC#" + account.id().value());
        item.put("entityType", "ACCOUNT");
        item.put("accountId", account.id().value());
        item.put("name", account.name());
        item.put("type", account.type().name());
        item.put("lastFourDigits", account.lastFourDigits());
        item.put("currency", account.currency());
        item.put("balanceAmount", account.currentBalance().amount().toPlainString());
        return item;
    }

    public static FinancialAccount toAccount(Map<String, String> item) {
        return new FinancialAccount(
            new AccountId(item.get("accountId")),
            item.get("name"),
            AccountType.valueOf(item.get("type")),
            item.get("lastFourDigits"),
            item.get("currency"),
            new Money(new BigDecimal(item.get("balanceAmount")), item.get("currency"))
        );
    }

    public static Map<String, String> fromTransaction(String userId, Transaction transaction) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "TXN#" + transaction.timestamp() + "#" + transaction.id().value());
        item.put("entityType", "TRANSACTION");
        item.put("txnId", transaction.id().value());
        item.put("amount", transaction.amount().amount().toPlainString());
        item.put("currency", transaction.amount().currency());
        item.put("type", transaction.type().name());
        item.put("timestamp", transaction.timestamp().toString());
        item.put("merchantName", transaction.merchantName());
        item.put("accountId", transaction.accountId().value());
        if (transaction.categoryId() != null) {
            item.put("categoryId", transaction.categoryId());
        }
        item.put("ingestionSource", transaction.ingestionSource().name());
        item.put("reconciliationStatus", transaction.reconciliationStatus().name());
        item.put("netPersonalExpense", transaction.netPersonalExpense().amount().toPlainString());
        return item;
    }

    public static Transaction toTransaction(Map<String, String> item) {
        return new Transaction(
            new TransactionId(item.get("txnId")),
            new Money(new BigDecimal(item.get("amount")), item.get("currency")),
            TransactionType.valueOf(item.get("type")),
            LocalDateTime.parse(item.get("timestamp")),
            item.get("merchantName"),
            new AccountId(item.get("accountId")),
            item.get("categoryId"),
            IngestionSource.valueOf(item.get("ingestionSource")),
            ReconciliationStatus.valueOf(item.get("reconciliationStatus")),
            new Money(new BigDecimal(item.get("netPersonalExpense")), item.get("currency"))
        );
    }
}
