package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.LanguageModelUsageRepository;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.UpdateItemRequest;

import java.time.YearMonth;
import java.util.Map;
import java.util.Objects;

/**
 * A durable, globally scoped circuit breaker for paid model requests.
 */
public final class AwsDynamoDbLanguageModelUsageRepository implements LanguageModelUsageRepository {
    private final DynamoDbClient client;
    private final String tableName;

    public AwsDynamoDbLanguageModelUsageRepository(DynamoDbClient client, String tableName) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
    }

    @Override
    public boolean reserve(String provider, YearMonth month, int maximumRequests) {
        if (provider == null || !provider.matches("[A-Z_]+") || maximumRequests < 1) {
            throw new IllegalArgumentException("provider and maximumRequests must be valid");
        }
        try {
            client.updateItem(UpdateItemRequest.builder()
                .tableName(tableName)
                .key(Map.of(
                    "PK", text("SYSTEM#LANGUAGE_MODEL"),
                    "SK", text("LLM_USAGE#" + provider + "#" + month)
                ))
                .updateExpression(
                    "SET #entity = :entity, #provider = :provider, #month = :month, "
                        + "#calls = if_not_exists(#calls, :zero) + :one"
                )
                .conditionExpression("attribute_not_exists(#calls) OR #calls < :maximum")
                .expressionAttributeNames(Map.of(
                    "#entity", "entityType", "#provider", "provider", "#month", "month", "#calls", "calls"
                ))
                .expressionAttributeValues(Map.of(
                    ":entity", text("LANGUAGE_MODEL_USAGE"),
                    ":provider", text(provider),
                    ":month", text(month.toString()),
                    ":zero", AttributeValue.fromN("0"),
                    ":one", AttributeValue.fromN("1"),
                    ":maximum", AttributeValue.fromN(Integer.toString(maximumRequests))
                ))
                .build());
            return true;
        } catch (ConditionalCheckFailedException exception) {
            return false;
        }
    }

    private AttributeValue text(String value) {
        return AttributeValue.fromS(value);
    }
}
