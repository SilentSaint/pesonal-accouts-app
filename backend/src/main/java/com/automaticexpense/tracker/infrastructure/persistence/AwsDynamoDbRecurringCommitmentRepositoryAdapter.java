package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.RecurringCommitmentRepository;
import com.automaticexpense.tracker.domain.RecurringCommitment;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
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

/** Authoritative, principal-scoped persistence for detected and confirmed recurring commitments. */
public final class AwsDynamoDbRecurringCommitmentRepositoryAdapter implements RecurringCommitmentRepository {
    private static final String USER_PREFIX = "USER#";
    private static final String RECURRING_PREFIX = "RECUR#";

    private final DynamoDbClient client;
    private final String tableName;
    private final String userPartitionKey;

    public AwsDynamoDbRecurringCommitmentRepositoryAdapter(
        DynamoDbClient client, String tableName, String authenticatedUserId
    ) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
        this.userPartitionKey = USER_PREFIX + Objects.requireNonNull(
            authenticatedUserId, "authenticatedUserId cannot be null"
        );
    }

    @Override
    public void save(RecurringCommitment commitment) {
        client.putItem(PutItemRequest.builder()
            .tableName(tableName)
            .item(toItem(RecurringCommitmentDynamoDbMapper.from(userId(), commitment)))
            .build());
    }

    @Override
    public Optional<RecurringCommitment> findById(String commitmentId) {
        Map<String, AttributeValue> item = client.getItem(GetItemRequest.builder()
            .tableName(tableName)
            .key(key(RECURRING_PREFIX + Objects.requireNonNull(commitmentId, "commitmentId cannot be null")))
            .consistentRead(true)
            .build()).item();
        return item.isEmpty() ? Optional.empty() : Optional.of(RecurringCommitmentDynamoDbMapper.to(fromItem(item)));
    }

    @Override
    public Optional<RecurringCommitment> findByCandidateKey(String candidateKey) {
        Objects.requireNonNull(candidateKey, "candidateKey cannot be null");
        return findAll().stream()
            .filter(commitment -> candidateKey.equals(commitment.candidateKey()))
            .findFirst();
    }

    @Override
    public List<RecurringCommitment> findAll() {
        List<RecurringCommitment> commitments = new ArrayList<>();
        Map<String, AttributeValue> startKey = null;
        do {
            QueryResponse response = client.query(QueryRequest.builder()
                .tableName(tableName)
                .keyConditionExpression("PK = :pk AND begins_with(SK, :sk)")
                .expressionAttributeValues(Map.of(
                    ":pk", AttributeValue.fromS(userPartitionKey),
                    ":sk", AttributeValue.fromS(RECURRING_PREFIX)
                ))
                .exclusiveStartKey(startKey)
                .build());
            response.items().stream()
                .map(this::fromItem)
                .map(RecurringCommitmentDynamoDbMapper::to)
                .forEach(commitments::add);
            startKey = response.lastEvaluatedKey().isEmpty() ? null : response.lastEvaluatedKey();
        } while (startKey != null);
        return commitments;
    }

    private Map<String, AttributeValue> key(String sortKey) {
        return Map.of("PK", AttributeValue.fromS(userPartitionKey), "SK", AttributeValue.fromS(sortKey));
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
