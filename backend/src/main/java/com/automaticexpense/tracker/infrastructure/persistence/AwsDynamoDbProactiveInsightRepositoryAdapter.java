package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.ProactiveInsightLedger;
import com.automaticexpense.tracker.application.port.out.ProactiveInsightRepository;
import com.automaticexpense.tracker.domain.*;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.*;

/**
 * Single-table persistence for proactive insights and their durable idempotency keys.
 */
public final class AwsDynamoDbProactiveInsightRepositoryAdapter
    implements ProactiveInsightRepository, ProactiveInsightLedger {
    private static final String USER_PREFIX = "USER#";
    private static final String INSIGHT_PREFIX = "INSIGHT#";
    private static final String TRANSACTION_PREFIX = "TXN#";

    private final DynamoDbClient client;
    private final String tableName;

    public AwsDynamoDbProactiveInsightRepositoryAdapter(DynamoDbClient client, String tableName) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
    }

    @Override
    public FinancialSnapshot load(String userId, Instant asOf, ZoneId timezone) {
        List<Transaction> transactions = new ArrayList<>();
        Map<String, AttributeValue> startKey = null;
        do {
            QueryResponse response = client.query(QueryRequest.builder()
                .tableName(tableName)
                .keyConditionExpression("PK = :pk AND begins_with(SK, :prefix)")
                .expressionAttributeValues(Map.of(":pk", text(userPartition(userId)), ":prefix", text(TRANSACTION_PREFIX)))
                .exclusiveStartKey(startKey)
                .build());
            response.items().stream().map(this::strings).map(DynamoDbItem::toTransaction).forEach(transactions::add);
            startKey = response.lastEvaluatedKey().isEmpty() ? null : response.lastEvaluatedKey();
        } while (startKey != null);
        return new FinancialSnapshot(asOf, timezone, transactions);
    }

    @Override
    public boolean saveIfAbsent(String userId, ProactiveInsight insight) {
        Objects.requireNonNull(insight, "insight cannot be null");
        Map<String, AttributeValue> card = attributes(cardItem(userId, insight));
        Map<String, AttributeValue> deduplication = Map.of(
            "PK", text(userPartition(userId)),
            "SK", text("INSIGHT_DEDUP#" + insight.deduplicationKey()),
            "entityType", text("INSIGHT_DEDUPLICATION"),
            "insightId", text(insight.id())
        );
        try {
            client.transactWriteItems(TransactWriteItemsRequest.builder().transactItems(
                TransactWriteItem.builder().put(Put.builder().tableName(tableName).item(card)
                    .conditionExpression("attribute_not_exists(PK) AND attribute_not_exists(SK)").build()).build(),
                TransactWriteItem.builder().put(Put.builder().tableName(tableName).item(deduplication)
                    .conditionExpression("attribute_not_exists(PK) AND attribute_not_exists(SK)").build()).build()
            ).build());
            return true;
        } catch (TransactionCanceledException exception) {
            if (exception.cancellationReasons().stream()
                .anyMatch(reason -> "ConditionalCheckFailed".equals(reason.code()))) {
                return false;
            }
            throw exception;
        }
    }

    @Override
    public List<ProactiveInsight> list(String userId) {
        List<ProactiveInsight> insights = new ArrayList<>();
        Map<String, AttributeValue> startKey = null;
        do {
            QueryResponse response = client.query(QueryRequest.builder()
                .tableName(tableName)
                .keyConditionExpression("PK = :pk AND begins_with(SK, :prefix)")
                .expressionAttributeValues(Map.of(":pk", text(userPartition(userId)), ":prefix", text(INSIGHT_PREFIX)))
                .exclusiveStartKey(startKey)
                .scanIndexForward(false)
                .build());
            response.items().stream().map(this::strings).map(this::toInsight).forEach(insights::add);
            startKey = response.lastEvaluatedKey().isEmpty() ? null : response.lastEvaluatedKey();
        } while (startKey != null);
        return List.copyOf(insights);
    }

    @Override
    public void dismiss(String userId, String insightId) {
        findById(userId, insightId).ifPresent(item -> client.updateItem(UpdateItemRequest.builder()
            .tableName(tableName)
            .key(Map.of("PK", text(userPartition(userId)), "SK", text(item.get("SK"))))
            .updateExpression("SET lifecycleState = :dismissed")
            .expressionAttributeValues(Map.of(":dismissed", text(InsightLifecycleState.DISMISSED.name())))
            .build()));
    }

    private Optional<Map<String, String>> findById(String userId, String insightId) {
        return listItems(userId).stream().filter(item -> insightId.equals(item.get("insightId"))).findFirst();
    }

    private List<Map<String, String>> listItems(String userId) {
        List<Map<String, String>> items = new ArrayList<>();
        Map<String, AttributeValue> startKey = null;
        do {
            QueryResponse response = client.query(QueryRequest.builder()
                .tableName(tableName)
                .keyConditionExpression("PK = :pk AND begins_with(SK, :prefix)")
                .expressionAttributeValues(Map.of(":pk", text(userPartition(userId)), ":prefix", text(INSIGHT_PREFIX)))
                .exclusiveStartKey(startKey).build());
            response.items().stream().map(this::strings).forEach(items::add);
            startKey = response.lastEvaluatedKey().isEmpty() ? null : response.lastEvaluatedKey();
        } while (startKey != null);
        return items;
    }

    private Map<String, String> cardItem(String userId, ProactiveInsight insight) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", userPartition(userId));
        item.put("SK", INSIGHT_PREFIX + insight.createdAt() + "#" + insight.id());
        item.put("entityType", "PROACTIVE_INSIGHT");
        item.put("insightId", insight.id());
        item.put("type", insight.type().name());
        item.put("classification", insight.classification().name());
        item.put("title", insight.title());
        item.put("message", insight.message());
        item.put("currentAmount", insight.currentAmount().amount().toPlainString());
        item.put("baselineAmount", insight.baselineAmount().amount().toPlainString());
        item.put("currency", insight.currentAmount().currency());
        item.put("baselineLabel", insight.baselineLabel());
        item.put("confidence", insight.confidence().toPlainString());
        item.put("asOf", insight.asOf().toString());
        item.put("freshnessAsOf", insight.freshnessAsOf().toString());
        item.put("formulaId", insight.formula().id());
        item.put("formulaVersion", insight.formula().version());
        item.put("sourceCount", Integer.toString(insight.evidence().sourceCount()));
        item.put("periodStart", insight.evidence().drillDown().period().start().toString());
        item.put("periodEnd", insight.evidence().drillDown().period().end().toString());
        put(item, "categoryId", insight.evidence().drillDown().categoryId());
        put(item, "merchantName", insight.evidence().drillDown().merchantName());
        item.put("matchingTransactions", encodeEvidence(insight.matchingTransactions()));
        item.put("assumptions", String.join("\u001f", insight.assumptions()));
        item.put("warnings", insight.warnings().stream().map(Enum::name).reduce((a, b) -> a + "," + b).orElse(""));
        item.put("deduplicationKey", insight.deduplicationKey());
        item.put("createdAt", insight.createdAt().toString());
        item.put("expiresAt", insight.expiresAt().toString());
        item.put("lifecycleState", insight.lifecycleState().name());
        return item;
    }

    private ProactiveInsight toInsight(Map<String, String> item) {
        String currency = item.get("currency");
        DateRange period = new DateRange(java.time.LocalDate.parse(item.get("periodStart")),
            java.time.LocalDate.parse(item.get("periodEnd")));
        return new ProactiveInsight(
            item.get("insightId"), ProactiveInsightType.valueOf(item.get("type")),
            IntelligenceClassification.valueOf(item.get("classification")), item.get("title"), item.get("message"),
            Money.of(item.get("currentAmount"), currency), Money.of(item.get("baselineAmount"), currency),
            item.get("baselineLabel"), new BigDecimal(item.get("confidence")), Instant.parse(item.get("asOf")),
            Instant.parse(item.get("freshnessAsOf")), new FormulaReference(item.get("formulaId"), item.get("formulaVersion")),
            new EvidenceMetadata(Integer.parseInt(item.get("sourceCount")),
                new DrillDownReference(period, currency, Set.of(), item.get("categoryId"), item.get("merchantName"))),
            decodeEvidence(item.getOrDefault("matchingTransactions", ""), currency),
            split(item.get("assumptions"), "\u001f"), split(item.get("warnings"), ",").stream()
                .filter(value -> !value.isBlank()).map(IntelligenceWarning::valueOf).toList(),
            item.get("deduplicationKey"), Instant.parse(item.get("createdAt")), Instant.parse(item.get("expiresAt")),
            InsightLifecycleState.valueOf(item.get("lifecycleState"))
        );
    }

    private String encodeEvidence(List<TransactionEvidence> evidence) {
        return evidence.stream().map(value -> String.join("\u001e", value.transactionId(), value.timestamp().toString(),
            escape(value.merchantName()), value.personalSpend().amount().toPlainString())).reduce((a, b) -> a + "\u001d" + b)
            .orElse("");
    }

    private List<TransactionEvidence> decodeEvidence(String value, String currency) {
        if (value.isBlank()) return List.of();
        return Arrays.stream(value.split("\u001d", -1)).map(encoded -> encoded.split("\u001e", -1))
            .map(fields -> new TransactionEvidence(fields[0], LocalDateTime.parse(fields[1]), unescape(fields[2]),
                Money.of(fields[3], currency))).toList();
    }

    private String escape(String value) {
        return value.replace("\\", "\\\\").replace("\u001d", "\\u001d").replace("\u001e", "\\u001e");
    }

    private String unescape(String value) {
        return value.replace("\\u001e", "\u001e").replace("\\u001d", "\u001d").replace("\\\\", "\\");
    }

    private List<String> split(String value, String delimiter) {
        return value == null || value.isBlank() ? List.of() : List.of(value.split(delimiter, -1));
    }

    private void put(Map<String, String> item, String key, String value) {
        if (value != null) item.put(key, value);
    }

    private Map<String, AttributeValue> attributes(Map<String, String> item) {
        Map<String, AttributeValue> attributes = new HashMap<>();
        item.forEach((key, value) -> attributes.put(key, text(value)));
        return attributes;
    }

    private Map<String, String> strings(Map<String, AttributeValue> item) {
        Map<String, String> values = new HashMap<>();
        item.forEach((key, value) -> values.put(key, value.s()));
        return values;
    }

    private AttributeValue text(String value) {
        return AttributeValue.fromS(value);
    }

    private String userPartition(String userId) {
        if (userId == null || userId.isBlank()) throw new IllegalArgumentException("userId cannot be blank");
        return USER_PREFIX + userId;
    }
}
