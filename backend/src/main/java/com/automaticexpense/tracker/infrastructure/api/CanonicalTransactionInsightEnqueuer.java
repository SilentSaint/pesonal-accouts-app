package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.DynamodbEvent;
import com.amazonaws.services.lambda.runtime.events.models.dynamodb.AttributeValue;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;

import java.time.Instant;
import java.util.Map;
import java.util.Objects;

/**
 * Converts canonical transaction stream records into minimal, bounded refresh commands.
 * It defensively ignores every non-transaction image, including derived insight records.
 */
public final class CanonicalTransactionInsightEnqueuer implements RequestHandler<DynamodbEvent, Void> {
    private static final ObjectMapper JSON = new ObjectMapper();
    private final SqsClient queue;
    private final String queueUrl;
    private final DynamoDbClient owners;
    private final String tableName;
    private final InstantSource clock;

    public CanonicalTransactionInsightEnqueuer() {
        this(
            SqsClient.create(), requiredEnvironment("INSIGHT_REFRESH_QUEUE_URL"),
            DynamoDbClient.create(), requiredEnvironment("TABLE_NAME"), Instant::now
        );
    }

    public CanonicalTransactionInsightEnqueuer(SqsClient queue, String queueUrl, InstantSource clock) {
        this(queue, queueUrl, null, null, clock);
    }

    private CanonicalTransactionInsightEnqueuer(
        SqsClient queue, String queueUrl, DynamoDbClient owners, String tableName, InstantSource clock
    ) {
        this.queue = Objects.requireNonNull(queue, "queue cannot be null");
        this.queueUrl = Objects.requireNonNull(queueUrl, "queueUrl cannot be null");
        this.owners = owners;
        this.tableName = tableName;
        this.clock = Objects.requireNonNull(clock, "clock cannot be null");
    }

    @Override
    public Void handleRequest(DynamodbEvent event, Context context) {
        if (event == null || event.getRecords() == null) throw new IllegalArgumentException("DynamoDB records are required");
        for (DynamodbEvent.DynamodbStreamRecord record : event.getRecords()) {
            Map<String, AttributeValue> image = record.getDynamodb() == null ? null : record.getDynamodb().getNewImage();
            if (!isCanonicalTransactionChange(record, image)) continue;
            String partition = string(image, "PK");
            String userId = partition.substring("USER#".length());
            String currency = string(image, "currency");
            queue.sendMessage(SendMessageRequest.builder().queueUrl(queueUrl)
                .messageBody(message(userId, currency, record.getEventID())).build());
            recordInsightOwner(userId);
        }
        return null;
    }

    private void recordInsightOwner(String userId) {
        if (owners == null) return;
        owners.putItem(PutItemRequest.builder().tableName(tableName).item(Map.of(
            "PK", software.amazon.awssdk.services.dynamodb.model.AttributeValue.fromS("INSIGHT_OWNERS"),
            "SK", software.amazon.awssdk.services.dynamodb.model.AttributeValue.fromS("USER#" + userId),
            "entityType", software.amazon.awssdk.services.dynamodb.model.AttributeValue.fromS("INSIGHT_OWNER"),
            "userId", software.amazon.awssdk.services.dynamodb.model.AttributeValue.fromS(userId)
        )).build());
    }

    private boolean isCanonicalTransactionChange(
        DynamodbEvent.DynamodbStreamRecord record, Map<String, AttributeValue> image
    ) {
        if (!("INSERT".equals(record.getEventName()) || "MODIFY".equals(record.getEventName())) || image == null) return false;
        String partition = string(image, "PK");
        String sort = string(image, "SK");
        return "TRANSACTION".equals(string(image, "entityType"))
            && partition != null && partition.startsWith("USER#")
            && sort != null && sort.startsWith("TXN#");
    }

    private String message(String userId, String currency, String eventId) {
        try {
            return JSON.writeValueAsString(Map.of(
                "userId", userId, "currency", currency, "timezone", "Asia/Kolkata",
                "asOf", clock.now().toString(), "eventId", eventId == null ? "" : eventId
            ));
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to serialize insight refresh message", exception);
        }
    }

    private String string(Map<String, AttributeValue> image, String key) {
        AttributeValue value = image.get(key);
        return value == null ? null : value.getS();
    }

    private static String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) throw new IllegalStateException(name + " is not configured");
        return value;
    }

    @FunctionalInterface
    public interface InstantSource {
        Instant now();
    }
}
