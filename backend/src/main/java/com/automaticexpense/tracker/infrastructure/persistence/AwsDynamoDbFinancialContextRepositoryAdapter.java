package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.FinancialContextRepository;
import com.automaticexpense.tracker.domain.FinancialContextItem;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.DeleteItemRequest;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/** Authoritative per-principal context persistence in the existing DynamoDB single table. */
public final class AwsDynamoDbFinancialContextRepositoryAdapter implements FinancialContextRepository {
    private static final String USER_PREFIX = "USER#";
    private static final String CONTEXT_PREFIX = "CONTEXT#";

    private final DynamoDbClient client;
    private final String tableName;
    private final String userPartitionKey;

    public AwsDynamoDbFinancialContextRepositoryAdapter(
        DynamoDbClient client, String tableName, String verifiedPrincipal
    ) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
        this.userPartitionKey = USER_PREFIX + Objects.requireNonNull(
            verifiedPrincipal, "verifiedPrincipal cannot be null"
        );
    }

    @Override
    public void save(FinancialContextItem item) {
        client.putItem(PutItemRequest.builder()
            .tableName(tableName)
            .item(toItem(DynamoDbItem.fromFinancialContextItem(principal(), item)))
            .build());
    }

    @Override
    public Optional<FinancialContextItem> findById(String id) {
        Map<String, AttributeValue> item = client.getItem(GetItemRequest.builder()
            .tableName(tableName)
            .key(key(id))
            .consistentRead(true)
            .build()).item();
        return item.isEmpty() ? Optional.empty() : Optional.of(DynamoDbItem.toFinancialContextItem(fromItem(item)));
    }

    @Override
    public List<FinancialContextItem> findAll() {
        List<FinancialContextItem> contexts = new ArrayList<>();
        Map<String, AttributeValue> lastEvaluatedKey = null;
        do {
            QueryRequest.Builder request = QueryRequest.builder()
                .tableName(tableName)
                .keyConditionExpression("PK = :pk AND begins_with(SK, :sk)")
                .expressionAttributeValues(Map.of(
                    ":pk", AttributeValue.fromS(userPartitionKey),
                    ":sk", AttributeValue.fromS(CONTEXT_PREFIX)
                ));
            if (lastEvaluatedKey != null) {
                request.exclusiveStartKey(lastEvaluatedKey);
            }
            QueryResponse response = client.query(request.build());
            contexts.addAll(response.items().stream()
                .map(this::fromItem)
                .map(DynamoDbItem::toFinancialContextItem)
                .toList());
            lastEvaluatedKey = response.lastEvaluatedKey();
        } while (lastEvaluatedKey != null && !lastEvaluatedKey.isEmpty());
        return List.copyOf(contexts);
    }

    @Override
    public void delete(String id) {
        client.deleteItem(DeleteItemRequest.builder().tableName(tableName).key(key(id)).build());
    }

    private Map<String, AttributeValue> key(String id) {
        return Map.of("PK", AttributeValue.fromS(userPartitionKey), "SK", AttributeValue.fromS(CONTEXT_PREFIX + id));
    }

    private Map<String, AttributeValue> toItem(Map<String, String> item) {
        Map<String, AttributeValue> result = new HashMap<>();
        item.forEach((name, value) -> result.put(name, AttributeValue.fromS(value)));
        return result;
    }

    private Map<String, String> fromItem(Map<String, AttributeValue> item) {
        Map<String, String> result = new HashMap<>();
        item.forEach((name, value) -> result.put(name, value.s()));
        return result;
    }

    private String principal() {
        return userPartitionKey.substring(USER_PREFIX.length());
    }
}
