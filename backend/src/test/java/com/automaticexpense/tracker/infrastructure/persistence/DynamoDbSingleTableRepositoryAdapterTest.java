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
}
