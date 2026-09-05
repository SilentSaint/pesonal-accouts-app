package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.VendorRuleRepository;
import com.automaticexpense.tracker.domain.VendorCategoryRule;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * Per-principal DynamoDB adapter for the single-table {@code RULE#<PayeeKey>} access pattern.
 */
public final class AwsDynamoDbVendorRuleRepositoryAdapter implements VendorRuleRepository {
    private static final String USER_PREFIX = "USER#";
    private static final String RULE_PREFIX = "RULE#";

    private final DynamoDbClient client;
    private final String tableName;
    private final String userPartitionKey;

    public AwsDynamoDbVendorRuleRepositoryAdapter(
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
    public void save(VendorCategoryRule rule) {
        client.putItem(PutItemRequest.builder()
            .tableName(tableName)
            .item(toItem(DynamoDbItem.fromVendorRule(userId(), rule)))
            .build());
    }

    @Override
    public Optional<VendorCategoryRule> findByPayeeKey(String payeeKey) {
        Map<String, AttributeValue> item = client.getItem(GetItemRequest.builder()
            .tableName(tableName)
            .key(key(RULE_PREFIX + VendorCategoryRule.normalizePayeeKey(payeeKey)))
            .consistentRead(true)
            .build()).item();
        return item.isEmpty() ? Optional.empty() : Optional.of(DynamoDbItem.toVendorRule(fromItem(item)));
    }

    @Override
    public List<VendorCategoryRule> findAll() {
        return client.query(QueryRequest.builder()
                .tableName(tableName)
                .keyConditionExpression("PK = :pk AND begins_with(SK, :sk)")
                .expressionAttributeValues(Map.of(
                    ":pk", AttributeValue.fromS(userPartitionKey),
                    ":sk", AttributeValue.fromS(RULE_PREFIX)
                ))
                .build())
            .items().stream()
            .map(this::fromItem)
            .map(DynamoDbItem::toVendorRule)
            .toList();
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
