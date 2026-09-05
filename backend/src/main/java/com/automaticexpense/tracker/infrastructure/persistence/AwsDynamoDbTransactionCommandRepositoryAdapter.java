package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.TransactionCommand;
import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.application.port.out.TransactionCommandRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IngestionSource;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.automaticexpense.tracker.domain.TransactionCommandStatus;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.TransactionType;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.ReturnValue;
import software.amazon.awssdk.services.dynamodb.model.UpdateItemRequest;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * Stores commands at their stable key: USER#{scope}/CMD#{client-generated-id}.
 */
public final class AwsDynamoDbTransactionCommandRepositoryAdapter implements TransactionCommandRepository {
    private static final String USER_PREFIX = "USER#";
    private static final String COMMAND_PREFIX = "CMD#";

    private final DynamoDbClient client;
    private final String tableName;

    public AwsDynamoDbTransactionCommandRepositoryAdapter(DynamoDbClient client, String tableName) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
    }

    @Override
    public boolean create(TransactionCommand command) {
        try {
            client.putItem(PutItemRequest.builder()
                .tableName(tableName)
                .item(toItem(command))
                .conditionExpression("attribute_not_exists(PK) AND attribute_not_exists(SK)")
                .build());
            return true;
        } catch (ConditionalCheckFailedException exception) {
            return false;
        }
    }

    @Override
    public Optional<TransactionCommand> find(String userScopeId, TransactionId id) {
        Map<String, AttributeValue> item = client.getItem(GetItemRequest.builder()
            .tableName(tableName)
            .key(key(userScopeId, id))
            .consistentRead(true)
            .build()).item();
        return item.isEmpty() ? Optional.empty() : Optional.of(fromItem(item));
    }

    @Override
    public boolean markEnqueued(TransactionCommandReference reference) {
        return update(
            reference,
            "SET enqueued = :true",
            "attribute_not_exists(enqueued) OR enqueued = :false",
            Map.of(":true", bool(true), ":false", bool(false))
        );
    }

    @Override
    public boolean retry(TransactionCommandReference reference) {
        return update(
            reference,
            "SET #status = :pending, enqueued = :false REMOVE failureReason",
            "#status = :failed",
            Map.of(":pending", text("PENDING"), ":failed", text("FAILED"))
        );
    }

    @Override
    public boolean claim(TransactionCommandReference reference) {
        return update(
            reference,
            "SET #status = :processing REMOVE failureReason",
            "#status IN (:pending, :processing)",
            Map.of(":pending", text("PENDING"), ":processing", text("PROCESSING"))
        );
    }

    @Override
    public boolean finish(
        TransactionCommandReference reference,
        TransactionCommandStatus status,
        String failureReason
    ) {
        if (!status.isTerminal()) {
            throw new IllegalArgumentException("Commands can only finish in a terminal status");
        }
        String expression = failureReason == null
            ? "SET #status = :status REMOVE failureReason"
            : "SET #status = :status, failureReason = :failureReason";
        Map<String, AttributeValue> values = new HashMap<>();
        values.put(":status", text(status.name()));
        values.put(":processing", text("PROCESSING"));
        if (failureReason != null) {
            values.put(":failureReason", text(failureReason));
        }
        return update(reference, expression, "#status = :processing", values);
    }

    private boolean update(
        TransactionCommandReference reference,
        String updateExpression,
        String conditionExpression,
        Map<String, AttributeValue> values
    ) {
        try {
            Map<String, String> names = expressionAttributeNames(
                updateExpression, conditionExpression
            );
            UpdateItemRequest.Builder request = UpdateItemRequest.builder()
                .tableName(tableName)
                .key(key(reference.userScopeId(), reference.commandId()))
                .updateExpression(updateExpression)
                .conditionExpression(conditionExpression)
                .expressionAttributeValues(values)
                .returnValues(ReturnValue.NONE);
            if (!names.isEmpty()) {
                request.expressionAttributeNames(names);
            }
            client.updateItem(request.build());
            return true;
        } catch (ConditionalCheckFailedException exception) {
            return false;
        }
    }

    private Map<String, AttributeValue> toItem(TransactionCommand command) {
        IngestTransactionCommand payload = command.payload();
        Map<String, AttributeValue> item = new HashMap<>();
        item.putAll(key(command.userScopeId(), command.id()));
        item.put("entityType", text("TRANSACTION_COMMAND"));
        item.put("commandId", text(command.id().value()));
        item.put("status", text(command.status().name()));
        item.put("enqueued", bool(command.enqueued()));
        item.put("amount", text(payload.amount().amount().toPlainString()));
        item.put("currency", text(payload.amount().currency()));
        item.put("type", text(payload.type().name()));
        item.put("timestamp", text(payload.timestamp().toString()));
        item.put("merchantName", text(payload.merchantName()));
        item.put("accountId", text(payload.accountId().value()));
        item.put("ingestionSource", text(payload.ingestionSource().name()));
        if (payload.categoryId() != null) {
            item.put("categoryId", text(payload.categoryId()));
        }
        putIfPresent(item, "subCategory", payload.subCategory());
        if (payload.netPersonalExpense() != null) {
            item.put("netPersonalExpense", text(payload.netPersonalExpense().amount().toPlainString()));
        }
        putIfPresent(item, "accountMask", payload.accountMask());
        putIfPresent(item, "referenceNumber", payload.referenceNumber());
        putIfPresent(item, "rawSnippet", payload.rawSnippet());
        putIfPresent(item, "transferCounterpartMask", payload.transferCounterpartMask());
        return item;
    }

    private TransactionCommand fromItem(Map<String, AttributeValue> item) {
        String currency = item.get("currency").s();
        IngestTransactionCommand payload = new IngestTransactionCommand(
            new Money(new BigDecimal(item.get("amount").s()), currency),
            TransactionType.valueOf(item.get("type").s()),
            LocalDateTime.parse(item.get("timestamp").s()),
            item.get("merchantName").s(),
            new AccountId(item.get("accountId").s()),
            item.containsKey("categoryId") ? item.get("categoryId").s() : null,
            IngestionSource.valueOf(item.get("ingestionSource").s()),
            optionalText(item, "subCategory"),
            item.containsKey("netPersonalExpense")
                ? new Money(new BigDecimal(item.get("netPersonalExpense").s()), currency)
                : new Money(new BigDecimal(item.get("amount").s()), currency),
            optionalText(item, "accountMask"),
            optionalText(item, "referenceNumber"),
            optionalText(item, "rawSnippet"),
            optionalText(item, "transferCounterpartMask")
        );
        return new TransactionCommand(
            userScope(item.get("PK").s()),
            new TransactionId(item.get("commandId").s()),
            payload,
            TransactionCommandStatus.valueOf(item.get("status").s()),
            item.containsKey("failureReason") ? item.get("failureReason").s() : null,
            item.containsKey("enqueued") && item.get("enqueued").bool()
        );
    }

    private Map<String, AttributeValue> key(String userScopeId, TransactionId id) {
        return Map.of("PK", text(USER_PREFIX + userScopeId), "SK", text(COMMAND_PREFIX + id.value()));
    }

    private String userScope(String partitionKey) {
        if (!partitionKey.startsWith(USER_PREFIX)) {
            throw new IllegalStateException("Unexpected transaction command partition key");
        }
        return partitionKey.substring(USER_PREFIX.length());
    }

    private static AttributeValue text(String value) {
        return AttributeValue.fromS(value);
    }

    static Map<String, String> expressionAttributeNames(
        String updateExpression,
        String conditionExpression
    ) {
        return updateExpression.contains("#status") || conditionExpression.contains("#status")
            ? Map.of("#status", "status")
            : Map.of();
    }

    private static AttributeValue bool(boolean value) {
        return AttributeValue.fromBool(value);
    }

    private static void putIfPresent(
        Map<String, AttributeValue> item,
        String field,
        String value
    ) {
        if (value != null) {
            item.put(field, text(value));
        }
    }

    private static String optionalText(Map<String, AttributeValue> item, String field) {
        return item.containsKey(field) ? item.get(field).s() : null;
    }
}
