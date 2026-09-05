package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.CardEmiRepository;
import com.automaticexpense.tracker.application.port.out.LoanRepository;
import com.automaticexpense.tracker.domain.CardEmiPlan;
import com.automaticexpense.tracker.domain.LoanAccount;
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

/** Principal-scoped production access to existing loan and card-EMI single-table records. */
public final class AwsDynamoDbLoanCardEmiRepositoryAdapter implements LoanRepository, CardEmiRepository {
    private static final String USER_PREFIX = "USER#";
    private static final String LOAN_PREFIX = "LOAN#";
    private static final String CARD_EMI_PREFIX = "CARD_EMI#";

    private final DynamoDbClient client;
    private final String tableName;
    private final String userPartitionKey;

    public AwsDynamoDbLoanCardEmiRepositoryAdapter(
        DynamoDbClient client, String tableName, String authenticatedUserId
    ) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
        this.userPartitionKey = USER_PREFIX + Objects.requireNonNull(
            authenticatedUserId, "authenticatedUserId cannot be null"
        );
    }

    @Override
    public void save(LoanAccount loan) {
        put(DynamoDbItem.fromLoanAccount(userId(), loan));
    }

    @Override
    public Optional<LoanAccount> findLoanById(String loanId) {
        return get(LOAN_PREFIX + loanId).map(DynamoDbItem::toLoanAccount);
    }

    @Override
    public List<LoanAccount> findAllActive() {
        return query(LOAN_PREFIX).stream().map(DynamoDbItem::toLoanAccount)
            .filter(loan -> !loan.isClosed()).toList();
    }

    @Override
    public List<LoanAccount> findAllLoans() {
        return query(LOAN_PREFIX).stream().map(DynamoDbItem::toLoanAccount).toList();
    }

    @Override
    public void save(CardEmiPlan plan) {
        put(DynamoDbItem.fromCardEmiPlan(userId(), plan));
    }

    @Override
    public Optional<CardEmiPlan> findEmiPlanById(String planId) {
        return query(CARD_EMI_PREFIX).stream().map(DynamoDbItem::toCardEmiPlan)
            .filter(plan -> plan.id().equals(planId)).findFirst();
    }

    @Override
    public List<CardEmiPlan> findActiveByCardId(String cardAccountId) {
        return findAllActiveEmiPlans().stream().filter(plan -> plan.cardAccountId().equals(cardAccountId)).toList();
    }

    @Override
    public List<CardEmiPlan> findAllActiveEmiPlans() {
        return query(CARD_EMI_PREFIX).stream().map(DynamoDbItem::toCardEmiPlan)
            .filter(plan -> !plan.isCompleted()).toList();
    }

    @Override
    public List<CardEmiPlan> findAllEmiPlans() {
        return query(CARD_EMI_PREFIX).stream().map(DynamoDbItem::toCardEmiPlan).toList();
    }

    private Optional<Map<String, String>> get(String sortKey) {
        Map<String, AttributeValue> item = client.getItem(GetItemRequest.builder()
            .tableName(tableName).key(key(sortKey)).consistentRead(true).build()).item();
        return item.isEmpty() ? Optional.empty() : Optional.of(fromItem(item));
    }

    private List<Map<String, String>> query(String prefix) {
        List<Map<String, String>> items = new ArrayList<>();
        Map<String, AttributeValue> startKey = null;
        do {
            QueryResponse response = client.query(QueryRequest.builder()
                .tableName(tableName)
                .keyConditionExpression("PK = :pk AND begins_with(SK, :sk)")
                .expressionAttributeValues(Map.of(
                    ":pk", AttributeValue.fromS(userPartitionKey), ":sk", AttributeValue.fromS(prefix)
                ))
                .exclusiveStartKey(startKey)
                .build());
            response.items().stream().map(this::fromItem).forEach(items::add);
            startKey = response.lastEvaluatedKey().isEmpty() ? null : response.lastEvaluatedKey();
        } while (startKey != null);
        return items;
    }

    private void put(Map<String, String> item) {
        client.putItem(PutItemRequest.builder().tableName(tableName).item(toItem(item)).build());
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
