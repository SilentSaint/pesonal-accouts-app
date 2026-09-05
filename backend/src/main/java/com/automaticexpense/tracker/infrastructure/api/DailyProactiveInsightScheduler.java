package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.ScheduledEvent;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

import java.time.Instant;
import java.util.Map;
import java.util.Objects;

/**
 * Schedules one bounded refresh message per user observed by the canonical transaction stream.
 */
public final class DailyProactiveInsightScheduler implements RequestHandler<ScheduledEvent, Void> {
    private static final ObjectMapper JSON = new ObjectMapper();
    private final DynamoDbClient dynamo;
    private final SqsClient queue;
    private final String tableName;
    private final String queueUrl;
    private final CanonicalTransactionInsightEnqueuer.InstantSource clock;

    public DailyProactiveInsightScheduler() {
        this(DynamoDbClient.create(), SqsClient.create(), requiredEnvironment("TABLE_NAME"),
            requiredEnvironment("INSIGHT_REFRESH_QUEUE_URL"), Instant::now);
    }

    public DailyProactiveInsightScheduler(
        DynamoDbClient dynamo, SqsClient queue, String tableName, String queueUrl,
        CanonicalTransactionInsightEnqueuer.InstantSource clock
    ) {
        this.dynamo = Objects.requireNonNull(dynamo, "dynamo cannot be null");
        this.queue = Objects.requireNonNull(queue, "queue cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
        this.queueUrl = Objects.requireNonNull(queueUrl, "queueUrl cannot be null");
        this.clock = Objects.requireNonNull(clock, "clock cannot be null");
    }

    @Override
    public Void handleRequest(ScheduledEvent event, Context context) {
        Map<String, AttributeValue> startKey = null;
        do {
            QueryResponse response = dynamo.query(QueryRequest.builder().tableName(tableName)
                .keyConditionExpression("PK = :owners AND begins_with(SK, :user)")
                .expressionAttributeValues(Map.of(
                    ":owners", AttributeValue.fromS("INSIGHT_OWNERS"),
                    ":user", AttributeValue.fromS("USER#")
                ))
                .projectionExpression("userId")
                .exclusiveStartKey(startKey).build());
            for (Map<String, AttributeValue> item : response.items()) {
                queue.sendMessage(SendMessageRequest.builder().queueUrl(queueUrl)
                    .messageBody(message(item.get("userId").s())).build());
            }
            startKey = response.lastEvaluatedKey().isEmpty() ? null : response.lastEvaluatedKey();
        } while (startKey != null);
        return null;
    }

    private String message(String userId) {
        try {
            return JSON.writeValueAsString(Map.of(
                "userId", userId, "currency", "INR", "timezone", "Asia/Kolkata", "asOf", clock.now().toString()
            ));
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to serialize daily insight refresh", exception);
        }
    }

    private static String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) throw new IllegalStateException(name + " is not configured");
        return value;
    }
}
