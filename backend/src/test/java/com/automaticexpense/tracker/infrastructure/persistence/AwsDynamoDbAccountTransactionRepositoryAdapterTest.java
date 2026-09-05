package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IngestionSource;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.TransactionType;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;

import java.lang.reflect.Proxy;
import java.time.LocalDateTime;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Queue;

import static org.assertj.core.api.Assertions.assertThat;

class AwsDynamoDbAccountTransactionRepositoryAdapterTest {

    @Test
    void readsEveryTransactionQueryPageForRecurringIncomeDetection() {
        Transaction first = transaction("credit-1", LocalDateTime.of(2026, 1, 31, 9, 0));
        Transaction second = transaction("credit-2", LocalDateTime.of(2026, 2, 28, 9, 0));
        Map<String, AttributeValue> lastKey = Map.of(
            "PK", AttributeValue.fromS("USER#income-scope"),
            "SK", AttributeValue.fromS("TXN#2026-01-31T09:00#credit-1")
        );
        Queue<QueryResponse> responses = new ArrayDeque<>(List.of(
            QueryResponse.builder().items(item(first)).lastEvaluatedKey(lastKey).build(),
            QueryResponse.builder().items(item(second)).build()
        ));
        List<QueryRequest> requests = new ArrayList<>();
        DynamoDbClient client = (DynamoDbClient) Proxy.newProxyInstance(
            getClass().getClassLoader(),
            new Class<?>[] {DynamoDbClient.class},
            (proxy, method, arguments) -> {
                if (method.getName().equals("query")) {
                    requests.add((QueryRequest) arguments[0]);
                    return responses.remove();
                }
                throw new UnsupportedOperationException(method.getName());
            }
        );

        List<Transaction> transactions =
            new AwsDynamoDbAccountTransactionRepositoryAdapter(client, "ExpenseTrackerData", "income-scope")
                .findAllTransactions();

        assertThat(transactions)
            .extracting(Transaction::id)
            .extracting(TransactionId::value)
            .containsExactly("credit-1", "credit-2");
        assertThat(requests).hasSize(2);
        assertThat(requests.get(1).exclusiveStartKey()).isEqualTo(lastKey);
    }

    private Transaction transaction(String id, LocalDateTime timestamp) {
        return new Transaction(
            new TransactionId(id), Money.of("75000.00", "INR"), TransactionType.CREDIT, timestamp,
            "Acme Payroll", new AccountId("income-account"), null, IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED, Money.of("75000.00", "INR")
        );
    }

    private Map<String, AttributeValue> item(Transaction transaction) {
        Map<String, AttributeValue> item = new HashMap<>();
        DynamoDbItem.fromTransaction("income-scope", transaction)
            .forEach((name, value) -> item.put(name, AttributeValue.fromS(value)));
        return item;
    }
}
