package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.IncomeSourceRepository;
import com.automaticexpense.tracker.domain.IncomeSource;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
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

/**
 * Principal-scoped DynamoDB repository using the {@code USER#<principal>, INCOME#<id>} access
 * pattern. Income sources and unconfirmed suggestions share the same authoritative record.
 */
public final class AwsDynamoDbIncomeSourceRepositoryAdapter implements IncomeSourceRepository {
    private static final String USER_PREFIX = "USER#";
    private static final String INCOME_PREFIX = "INCOME#";

    private final DynamoDbClient client;
    private final String tableName;
    private final String userPartitionKey;

    public AwsDynamoDbIncomeSourceRepositoryAdapter(
        DynamoDbClient client,
        String tableName,
        String authenticatedUserId
    ) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
        this.userPartitionKey = USER_PREFIX + Objects.requireNonNull(
            authenticatedUserId, "authenticatedUserId cannot be null"
        );
    }

    @Override
    public void save(IncomeSource source) {
        client.putItem(PutItemRequest.builder()
            .tableName(tableName)
            .item(toItem(DynamoDbItem.fromIncomeSource(userId(), source)))
            .build());
    }

    @Override
    public boolean replaceIfPending(IncomeSource source) {
        try {
            client.putItem(PutItemRequest.builder()
                .tableName(tableName)
                .item(toItem(DynamoDbItem.fromIncomeSource(userId(), source)))
                .conditionExpression("#status = :pending")
                .expressionAttributeNames(Map.of("#status", "confirmationStatus"))
                .expressionAttributeValues(Map.of(
                    ":pending", AttributeValue.fromS("PENDING")
                ))
                .build());
            return true;
        } catch (ConditionalCheckFailedException ignored) {
            return false;
        }
    }

    @Override
    public Optional<IncomeSource> findById(String incomeSourceId) {
        Map<String, AttributeValue> item = client.getItem(GetItemRequest.builder()
            .tableName(tableName)
            .key(key(INCOME_PREFIX + Objects.requireNonNull(incomeSourceId, "incomeSourceId cannot be null")))
            .consistentRead(true)
            .build())
            .item();
        return item.isEmpty() ? Optional.empty() : Optional.of(DynamoDbItem.toIncomeSource(fromItem(item)));
    }

    @Override
    public Optional<IncomeSource> findBySuggestionKey(String suggestionKey) {
        Objects.requireNonNull(suggestionKey, "suggestionKey cannot be null");
        return findAll().stream().filter(source -> suggestionKey.equals(source.suggestionKey())).findFirst();
    }

    @Override
    public List<IncomeSource> findAll() {
        List<IncomeSource> sources = new ArrayList<>();
        Map<String, AttributeValue> startKey = null;
        do {
            QueryResponse response = client.query(QueryRequest.builder()
                .tableName(tableName)
                .keyConditionExpression("PK = :pk AND begins_with(SK, :sk)")
                .expressionAttributeValues(Map.of(
                    ":pk", AttributeValue.fromS(userPartitionKey),
                    ":sk", AttributeValue.fromS(INCOME_PREFIX)
                ))
                .exclusiveStartKey(startKey)
                .build());
            response.items().stream()
                .map(this::fromItem)
                .map(DynamoDbItem::toIncomeSource)
                .forEach(sources::add);
            startKey = response.lastEvaluatedKey().isEmpty() ? null : response.lastEvaluatedKey();
        } while (startKey != null);
        return sources;
    }

    private Map<String, AttributeValue> key(String sortKey) {
        return Map.of(
            "PK", AttributeValue.fromS(userPartitionKey),
            "SK", AttributeValue.fromS(sortKey)
        );
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

    private String userId() {
        return userPartitionKey.substring(USER_PREFIX.length());
    }
}
