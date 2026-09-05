package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.FinancialGoalRepository;
import com.automaticexpense.tracker.domain.FinancialGoal;
import com.automaticexpense.tracker.domain.FinancialGoalLifecycle;
import com.automaticexpense.tracker.domain.GoalAllocation;
import com.automaticexpense.tracker.domain.GoalContribution;
import com.automaticexpense.tracker.domain.GoalContributionCadence;
import com.automaticexpense.tracker.domain.GoalContributionRule;
import com.automaticexpense.tracker.domain.GoalPriority;
import com.automaticexpense.tracker.domain.Money;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.Delete;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.Put;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;
import software.amazon.awssdk.services.dynamodb.model.TransactWriteItem;
import software.amazon.awssdk.services.dynamodb.model.TransactWriteItemsRequest;

import java.math.BigDecimal;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * Principal-scoped production repository for {@code USER#<principal>, GOAL#<goalId>} items.
 * Allocation claims are conditionally written in the same DynamoDB transaction as the goal, so
 * concurrent requests cannot assign an explicit savings allocation to multiple goals.
 */
public final class AwsDynamoDbFinancialGoalRepositoryAdapter implements FinancialGoalRepository {
    private static final String USER_PREFIX = "USER#";
    private static final String GOAL_PREFIX = "GOAL#";

    private final DynamoDbClient client;
    private final String tableName;
    private final String partitionKey;

    public AwsDynamoDbFinancialGoalRepositoryAdapter(
        DynamoDbClient client, String tableName, String authenticatedUserId
    ) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
        this.partitionKey = USER_PREFIX + Objects.requireNonNull(
            authenticatedUserId, "authenticatedUserId cannot be null"
        );
    }

    @Override
    public void save(FinancialGoal goal) {
        FinancialGoal existing = findById(goal.id()).orElse(null);
        List<TransactWriteItem> writes = new ArrayList<>();
        writes.add(TransactWriteItem.builder().put(Put.builder()
            .tableName(tableName)
            .item(attributes(toItem(goal)))
            .build()).build());
        for (GoalAllocation allocation : goal.allocations()) {
            writes.add(TransactWriteItem.builder().put(Put.builder()
                .tableName(tableName)
                .item(attributes(allocationClaim(goal.id(), allocation.reference())))
                .conditionExpression("attribute_not_exists(PK) OR #goalId = :goalId")
                .expressionAttributeNames(Map.of("#goalId", "goalId"))
                .expressionAttributeValues(Map.of(":goalId", AttributeValue.fromS(goal.id())))
                .build()).build());
        }
        if (existing != null) {
            for (GoalAllocation allocation : existing.allocations()) {
                boolean retained = goal.allocations().stream()
                    .anyMatch(current -> current.reference().equals(allocation.reference()));
                if (!retained) {
                    writes.add(TransactWriteItem.builder().delete(Delete.builder()
                        .tableName(tableName)
                        .key(allocationClaimKey(allocation.reference()))
                        .conditionExpression("#goalId = :goalId")
                        .expressionAttributeNames(Map.of("#goalId", "goalId"))
                        .expressionAttributeValues(Map.of(":goalId", AttributeValue.fromS(goal.id())))
                        .build()).build());
                }
            }
        }
        transact(writes);
    }

    @Override
    public Optional<FinancialGoal> findById(String id) {
        Map<String, AttributeValue> item = client.getItem(GetItemRequest.builder()
            .tableName(tableName)
            .consistentRead(true)
            .key(key(Objects.requireNonNull(id, "id cannot be null")))
            .build())
            .item();
        return item.isEmpty() ? Optional.empty() : Optional.of(fromItem(strings(item)));
    }

    @Override
    public List<FinancialGoal> findAll() {
        List<FinancialGoal> result = new ArrayList<>();
        Map<String, AttributeValue> startKey = null;
        do {
            QueryResponse response = client.query(QueryRequest.builder()
                .tableName(tableName)
                .keyConditionExpression("PK = :pk AND begins_with(SK, :sk)")
                .expressionAttributeValues(Map.of(
                    ":pk", AttributeValue.fromS(partitionKey),
                    ":sk", AttributeValue.fromS(GOAL_PREFIX)
                ))
                .exclusiveStartKey(startKey)
                .build());
            response.items().stream().map(this::strings).map(this::fromItem).forEach(result::add);
            startKey = response.lastEvaluatedKey().isEmpty() ? null : response.lastEvaluatedKey();
        } while (startKey != null);
        return result;
    }

    @Override
    public void deleteById(String id) {
        FinancialGoal existing = findById(id).orElse(null);
        if (existing == null) return;
        List<TransactWriteItem> writes = new ArrayList<>();
        writes.add(TransactWriteItem.builder().delete(Delete.builder()
            .tableName(tableName)
            .key(key(id))
            .build()).build());
        for (GoalAllocation allocation : existing.allocations()) {
            writes.add(TransactWriteItem.builder().delete(Delete.builder()
                .tableName(tableName)
                .key(allocationClaimKey(allocation.reference()))
                .conditionExpression("#goalId = :goalId")
                .expressionAttributeNames(Map.of("#goalId", "goalId"))
                .expressionAttributeValues(Map.of(":goalId", AttributeValue.fromS(id)))
                .build()).build());
        }
        transact(writes);
    }

    private Map<String, AttributeValue> key(String id) {
        return Map.of("PK", AttributeValue.fromS(partitionKey), "SK", AttributeValue.fromS(GOAL_PREFIX + id));
    }

    private Map<String, AttributeValue> allocationClaimKey(String allocationReference) {
        return Map.of("PK", AttributeValue.fromS(partitionKey), "SK", AttributeValue.fromS(
            "GOAL_ALLOCATION#" + allocationReference
        ));
    }

    private Map<String, String> allocationClaim(String goalId, String allocationReference) {
        Map<String, String> claim = new HashMap<>();
        claim.put("PK", partitionKey);
        claim.put("SK", "GOAL_ALLOCATION#" + allocationReference);
        claim.put("entityType", "FINANCIAL_GOAL_ALLOCATION");
        claim.put("goalId", goalId);
        return claim;
    }

    private void transact(List<TransactWriteItem> writes) {
        if (writes.size() > 25) {
            throw new IllegalArgumentException("financial goal allocation transaction exceeds DynamoDB limit");
        }
        client.transactWriteItems(TransactWriteItemsRequest.builder().transactItems(writes).build());
    }

    private Map<String, AttributeValue> attributes(Map<String, String> item) {
        Map<String, AttributeValue> attributes = new HashMap<>();
        item.forEach((key, value) -> attributes.put(key, AttributeValue.fromS(value)));
        return attributes;
    }

    private Map<String, String> strings(Map<String, AttributeValue> item) {
        Map<String, String> strings = new HashMap<>();
        item.forEach((key, value) -> strings.put(key, value.s()));
        return strings;
    }

    private Map<String, String> toItem(FinancialGoal goal) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", partitionKey);
        item.put("SK", GOAL_PREFIX + goal.id());
        item.put("entityType", "FINANCIAL_GOAL");
        item.put("goalId", goal.id());
        item.put("name", goal.name());
        item.put("targetAmount", goal.targetAmount().amount().toPlainString());
        item.put("currency", goal.targetAmount().currency());
        item.put("targetDate", goal.targetDate().toString());
        item.put("priority", goal.priority().name());
        item.put("lifecycle", goal.lifecycle().name());
        item.put("allocations", goal.allocations().stream().map(this::encodeAllocation).reduce((a, b) -> a + ";" + b)
            .orElse(""));
        item.put("contributions", goal.contributions().stream().map(this::encodeContribution)
            .reduce((a, b) -> a + ";" + b).orElse(""));
        if (goal.contributionRule().isConfigured()) {
            item.put("ruleAmount", goal.contributionRule().amount().amount().toPlainString());
            item.put("ruleCadence", goal.contributionRule().cadence().name());
        }
        return item;
    }

    private FinancialGoal fromItem(Map<String, String> item) {
        String currency = required(item, "currency");
        GoalContributionRule rule = item.containsKey("ruleAmount")
            ? new GoalContributionRule(
                Money.of(new BigDecimal(item.get("ruleAmount")), currency),
                GoalContributionCadence.valueOf(required(item, "ruleCadence"))
            )
            : GoalContributionRule.none();
        return new FinancialGoal(
            required(item, "goalId"),
            required(item, "name"),
            Money.of(new BigDecimal(required(item, "targetAmount")), currency),
            LocalDate.parse(required(item, "targetDate")),
            decodeAllocations(item.get("allocations"), currency),
            GoalPriority.valueOf(required(item, "priority")),
            rule,
            FinancialGoalLifecycle.valueOf(required(item, "lifecycle")),
            decodeContributions(item.get("contributions"), currency)
        );
    }

    private String encodeAllocation(GoalAllocation allocation) {
        return encoded(allocation.reference()) + "," + allocation.amount().amount().toPlainString() + ","
            + encoded(allocation.linkedAccountId());
    }

    private String encodeContribution(GoalContribution contribution) {
        return encoded(contribution.id()) + "," + contribution.amount().amount().toPlainString() + ","
            + contribution.contributedOn() + "," + encoded(contribution.evidenceReference());
    }

    private List<GoalAllocation> decodeAllocations(String serialized, String currency) {
        if (serialized == null || serialized.isBlank()) return List.of();
        List<GoalAllocation> allocations = new ArrayList<>();
        for (String entry : serialized.split(";")) {
            String[] values = entry.split(",", -1);
            if (values.length != 3) throw new IllegalArgumentException("Invalid persisted goal allocation");
            allocations.add(new GoalAllocation(
                decoded(values[0]), Money.of(new BigDecimal(values[1]), currency), decoded(values[2])
            ));
        }
        return List.copyOf(allocations);
    }

    private List<GoalContribution> decodeContributions(String serialized, String currency) {
        if (serialized == null || serialized.isBlank()) return List.of();
        List<GoalContribution> contributions = new ArrayList<>();
        for (String entry : serialized.split(";")) {
            String[] values = entry.split(",", -1);
            if (values.length != 4) throw new IllegalArgumentException("Invalid persisted goal contribution");
            contributions.add(new GoalContribution(
                decoded(values[0]), Money.of(new BigDecimal(values[1]), currency), LocalDate.parse(values[2]),
                decoded(values[3])
            ));
        }
        return List.copyOf(contributions);
    }

    private String encoded(String value) {
        return value == null ? "" : URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private String decoded(String value) {
        return value.isEmpty() ? null : URLDecoder.decode(value, StandardCharsets.UTF_8);
    }

    private String required(Map<String, String> item, String field) {
        String value = item.get(field);
        if (value == null || value.isBlank()) throw new IllegalArgumentException("Missing persisted " + field);
        return value;
    }
}
