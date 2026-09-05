package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;

import java.lang.reflect.Proxy;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class AwsDynamoDbFinancialSnapshotRepositoryAdapterTest {

    @Test
    void loadsEveryCanonicalTransactionPageFromOnlyTheAuthenticatedUsersPartition() {
        Transaction first = transaction("txn-1", LocalDateTime.of(2026, 8, 1, 10, 0));
        Transaction second = transaction("txn-2", LocalDateTime.of(2026, 8, 2, 10, 0));
        List<QueryRequest> requests = new ArrayList<>();
        DynamoDbClient client = client(requests, List.of(
            response(List.of(first), Map.of(
                "PK", AttributeValue.fromS("USER#scope-a"),
                "SK", AttributeValue.fromS("TXN#2026-08-01T10:00#txn-1")
            )),
            response(List.of(second), Map.of())
        ));
        AwsDynamoDbFinancialSnapshotRepositoryAdapter repository =
            new AwsDynamoDbFinancialSnapshotRepositoryAdapter(client, "ExpenseTrackerData", "scope-a");

        FinancialSnapshot snapshot = repository.load(new FinancialSnapshotRequest(
            Instant.parse("2026-08-31T00:00:00Z"),
            ZoneId.of("Asia/Kolkata"),
            Set.of(),
            "INR"
        ));

        assertThat(snapshot.canonicalTransactions()).extracting(transaction -> transaction.id().value())
            .containsExactly("txn-1", "txn-2");
        assertThat(requests).hasSize(2);
        assertThat(requests).allSatisfy(request -> {
            assertThat(request.keyConditionExpression()).contains("PK = :pk", "begins_with(SK");
            assertThat(request.expressionAttributeValues().get(":pk").s()).isEqualTo("USER#scope-a");
            assertThat(request.scanIndexForward()).isTrue();
        });
        assertThat(requests.get(1).exclusiveStartKey()).containsKey("SK");
    }

    @Test
    void returnsANewestFirstOpaqueCursorForFilteredEvidenceWithoutUsingAScan() {
        Transaction newest = transaction("txn-newest", LocalDateTime.of(2026, 8, 20, 10, 0));
        List<QueryRequest> requests = new ArrayList<>();
        DynamoDbClient client = client(requests, List.of(response(List.of(newest), Map.of(
            "PK", AttributeValue.fromS("USER#scope-a"),
            "SK", AttributeValue.fromS("TXN#2026-08-20T10:00#txn-newest")
        ))));
        AwsDynamoDbFinancialSnapshotRepositoryAdapter repository =
            new AwsDynamoDbFinancialSnapshotRepositoryAdapter(client, "ExpenseTrackerData", "scope-a");

        FinancialEvidencePage page = repository.load(new FinancialEvidenceQuery(
            new SpendingAnalyticsRequest(
                new DateRange(LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31)),
                "INR", Set.of(), null, null, 3
            ),
            Instant.parse("2026-08-31T00:00:00Z"),
            ZoneId.of("Asia/Kolkata"),
            1,
            null
        ));

        assertThat(page.transactions()).extracting(transaction -> transaction.id().value())
            .containsExactly("txn-newest");
        assertThat(page.nextCursor()).isNotBlank();
        QueryRequest request = requests.getFirst();
        assertThat(request.scanIndexForward()).isFalse();
        assertThat(request.filterExpression()).contains(
            "#status IN (:confirmed, :autoMerged)",
            "#type = :debit",
            "attribute_not_exists(#transfer)"
        );
        assertThat(request.expressionAttributeValues().get(":start").s())
            .isEqualTo("2026-07-31T18:30");
        assertThat(request.expressionAttributeValues().get(":end").s())
            .isEqualTo("2026-08-31T18:30");
    }

    private DynamoDbClient client(List<QueryRequest> requests, List<QueryResponse> responses) {
        ArrayDeque<QueryResponse> results = new ArrayDeque<>(responses);
        return (DynamoDbClient) Proxy.newProxyInstance(
            getClass().getClassLoader(),
            new Class<?>[] {DynamoDbClient.class},
            (proxy, method, arguments) -> {
                if ("query".equals(method.getName())) {
                    requests.add((QueryRequest) arguments[0]);
                    return results.removeFirst();
                }
                if ("serviceName".equals(method.getName())) {
                    return "DynamoDb";
                }
                if ("close".equals(method.getName())) {
                    return null;
                }
                throw new UnsupportedOperationException(method.getName());
            }
        );
    }

    private QueryResponse response(List<Transaction> transactions, Map<String, AttributeValue> lastKey) {
        return QueryResponse.builder()
            .items(transactions.stream().map(transaction -> DynamoDbItem.fromTransaction("scope-a", transaction))
                .map(this::attributes).toList())
            .lastEvaluatedKey(lastKey)
            .build();
    }

    private Map<String, AttributeValue> attributes(Map<String, String> item) {
        return item.entrySet().stream().collect(java.util.stream.Collectors.toMap(
            Map.Entry::getKey,
            entry -> AttributeValue.fromS(entry.getValue())
        ));
    }

    private Transaction transaction(String id, LocalDateTime timestamp) {
        return new Transaction(
            new TransactionId(id), Money.of("100.00", "INR"), TransactionType.DEBIT, timestamp,
            "Coffee", new AccountId("account-1"), "Dining", IngestionSource.MANUAL,
            ReconciliationStatus.CONFIRMED, Money.of("100.00", "INR")
        );
    }
}
