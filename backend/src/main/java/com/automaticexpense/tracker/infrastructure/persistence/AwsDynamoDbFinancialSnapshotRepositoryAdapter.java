package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.FinancialEvidenceRepository;
import com.automaticexpense.tracker.application.port.out.FinancialSnapshotRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.FinancialEvidencePage;
import com.automaticexpense.tracker.domain.FinancialEvidenceQuery;
import com.automaticexpense.tracker.domain.FinancialSnapshot;
import com.automaticexpense.tracker.domain.FinancialSnapshotRequest;
import com.automaticexpense.tracker.domain.Transaction;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;

import java.nio.charset.StandardCharsets;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * Principal-scoped DynamoDB query adapter for the canonical transaction ledger.
 */
public final class AwsDynamoDbFinancialSnapshotRepositoryAdapter
    implements FinancialSnapshotRepository, FinancialEvidenceRepository {

    private static final String USER_PREFIX = "USER#";
    private static final String TRANSACTION_PREFIX = "TXN#";

    private final DynamoDbClient client;
    private final String tableName;
    private final String userPartitionKey;

    public AwsDynamoDbFinancialSnapshotRepositoryAdapter(
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
    public FinancialSnapshot load(FinancialSnapshotRequest request) {
        List<Transaction> transactions = new ArrayList<>();
        Map<String, AttributeValue> startKey = null;
        do {
            QueryResponse response = client.query(snapshotRequest(request, startKey));
            response.items().stream()
                .map(this::stringItem)
                .map(DynamoDbItem::toTransaction)
                .forEach(transactions::add);
            startKey = response.lastEvaluatedKey().isEmpty() ? null : response.lastEvaluatedKey();
        } while (startKey != null);
        return new FinancialSnapshot(request.asOf(), request.timezone(), transactions);
    }

    @Override
    public FinancialEvidencePage load(FinancialEvidenceQuery query) {
        Map<String, AttributeValue> startKey = decodeCursor(query.cursor());
        List<Transaction> transactions = new ArrayList<>();
        Map<String, AttributeValue> nextKey = startKey;
        do {
            QueryResponse response = client.query(evidenceRequest(
                query, nextKey, query.pageSize() - transactions.size()
            ));
            response.items().stream()
                .map(this::stringItem)
                .map(DynamoDbItem::toTransaction)
                .forEach(transactions::add);
            nextKey = response.lastEvaluatedKey().isEmpty() ? null : response.lastEvaluatedKey();
        } while (transactions.size() < query.pageSize() && nextKey != null);

        return new FinancialEvidencePage(transactions, encodeCursor(nextKey));
    }

    private QueryRequest snapshotRequest(
        FinancialSnapshotRequest request,
        Map<String, AttributeValue> startKey
    ) {
        Map<String, AttributeValue> values = baseValues();
        values.put(":asOf", text(request.asOf().atOffset(ZoneOffset.UTC).toLocalDateTime().toString()));
        Map<String, String> names = baseNames();
        String filter = "#entity = :entity AND #timestamp <= :asOf";
        filter += accountFilter(request.accountIds(), values, names);
        return QueryRequest.builder()
            .tableName(tableName)
            .keyConditionExpression("PK = :pk AND begins_with(SK, :transactionPrefix)")
            .filterExpression(filter)
            .expressionAttributeNames(names)
            .expressionAttributeValues(values)
            .exclusiveStartKey(startKey)
            .scanIndexForward(true)
            .build();
    }

    private QueryRequest evidenceRequest(
        FinancialEvidenceQuery query,
        Map<String, AttributeValue> startKey,
        int limit
    ) {
        Map<String, AttributeValue> values = baseValues();
        Map<String, String> names = baseNames();
        values.put(":currency", text(query.filters().currency()));
        values.put(":debit", text("DEBIT"));
        values.put(":confirmed", text("CONFIRMED"));
        values.put(":autoMerged", text("AUTO_MERGED"));
        values.put(":start", text(utcStorageBoundary(
            query.filters().period().start(), query.timezone()
        )));
        values.put(":end", text(utcStorageBoundary(
            query.filters().period().end().plusDays(1), query.timezone()
        )));
        values.put(":asOf", text(query.asOf().atOffset(ZoneOffset.UTC).toLocalDateTime().toString()));
        names.put("#currency", "currency");
        names.put("#type", "type");
        names.put("#status", "reconciliationStatus");
        names.put("#transfer", "transferCounterpartMask");
        String filter = "#entity = :entity AND #currency = :currency AND #type = :debit"
            + " AND #status IN (:confirmed, :autoMerged)"
            + " AND #timestamp >= :start AND #timestamp < :end AND #timestamp <= :asOf"
            + " AND (attribute_not_exists(#transfer) OR #transfer = :empty)";
        values.put(":empty", text(""));
        filter += accountFilter(query.filters().accountIds(), values, names);
        if (query.filters().categoryId() != null) {
            names.put("#category", "categoryId");
            values.put(":category", text(query.filters().categoryId()));
            filter += " AND #category = :category";
        }
        if (query.filters().merchantName() != null) {
            names.put("#merchant", "merchantName");
            values.put(":merchant", text(query.filters().merchantName()));
            filter += " AND #merchant = :merchant";
        }
        return QueryRequest.builder()
            .tableName(tableName)
            .keyConditionExpression("PK = :pk AND begins_with(SK, :transactionPrefix)")
            .filterExpression(filter)
            .expressionAttributeNames(names)
            .expressionAttributeValues(values)
            .exclusiveStartKey(startKey)
            .limit(limit)
            .scanIndexForward(false)
            .build();
    }

    private String accountFilter(
        java.util.Set<AccountId> accountIds,
        Map<String, AttributeValue> values,
        Map<String, String> names
    ) {
        if (accountIds.isEmpty()) {
            return "";
        }
        names.put("#account", "accountId");
        List<String> placeholders = new ArrayList<>();
        int index = 0;
        for (AccountId accountId : accountIds) {
            String placeholder = ":account" + index++;
            placeholders.add(placeholder);
            values.put(placeholder, text(accountId.value()));
        }
        return " AND #account IN (" + String.join(", ", placeholders) + ")";
    }

    private Map<String, AttributeValue> baseValues() {
        return new HashMap<>(Map.of(
            ":pk", text(userPartitionKey),
            ":transactionPrefix", text(TRANSACTION_PREFIX),
            ":entity", text("TRANSACTION")
        ));
    }

    private Map<String, String> baseNames() {
        return new HashMap<>(Map.of(
            "#entity", "entityType",
            "#timestamp", "timestamp"
        ));
    }

    private Map<String, String> stringItem(Map<String, AttributeValue> item) {
        Map<String, String> values = new HashMap<>();
        item.forEach((key, value) -> values.put(key, value.s()));
        return values;
    }

    private Map<String, AttributeValue> decodeCursor(String cursor) {
        if (cursor == null || cursor.isBlank()) {
            return null;
        }
        try {
            String sortKey = new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8);
            if (!sortKey.startsWith(TRANSACTION_PREFIX)) {
                throw new IllegalArgumentException("cursor is invalid");
            }
            return Map.of("PK", text(userPartitionKey), "SK", text(sortKey));
        } catch (IllegalArgumentException exception) {
            throw new IllegalArgumentException("cursor is invalid", exception);
        }
    }

    private String encodeCursor(Map<String, AttributeValue> key) {
        if (key == null || key.isEmpty()) {
            return null;
        }
        AttributeValue sortKey = key.get("SK");
        if (sortKey == null || sortKey.s() == null || !sortKey.s().startsWith(TRANSACTION_PREFIX)) {
            throw new IllegalStateException("DynamoDB returned an invalid transaction cursor");
        }
        return Base64.getUrlEncoder().withoutPadding()
            .encodeToString(sortKey.s().getBytes(StandardCharsets.UTF_8));
    }

    private AttributeValue text(String value) {
        return AttributeValue.fromS(value);
    }

    private String utcStorageBoundary(java.time.LocalDate date, java.time.ZoneId timezone) {
        return date.atStartOfDay(timezone)
            .withZoneSameInstant(ZoneOffset.UTC)
            .toLocalDateTime()
            .toString();
    }
}
