package com.automaticexpense.tracker.infrastructure.messaging;

import com.automaticexpense.tracker.application.port.out.WebSocketEventPublisher;
import com.automaticexpense.tracker.domain.SyncEvent;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.apigatewaymanagementapi.ApiGatewayManagementApiClient;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.GoneException;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.PostToConnectionRequest;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.DeleteItemRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Objects;

/**
 * Driven adapter for the API Gateway WebSocket connection registry.
 */
public final class AwsApiGatewayWebSocketEventPublisher implements WebSocketEventPublisher {
    private final DynamoDbClient dynamoDb;
    private final ApiGatewayManagementApiClient gateway;
    private final String tableName;

    public AwsApiGatewayWebSocketEventPublisher(
        DynamoDbClient dynamoDb,
        ApiGatewayManagementApiClient gateway,
        String tableName
    ) {
        this.dynamoDb = Objects.requireNonNull(dynamoDb, "dynamoDb cannot be null");
        this.gateway = Objects.requireNonNull(gateway, "gateway cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
    }

    @Override
    public void broadcastToUser(String userId, SyncEvent event) {
        var connections = dynamoDb.query(QueryRequest.builder()
            .tableName(tableName)
            .keyConditionExpression("PK = :pk AND begins_with(SK, :prefix)")
            .expressionAttributeValues(Map.of(
                ":pk", AttributeValue.fromS("WSUSER#" + userId),
                ":prefix", AttributeValue.fromS("CONNECTION#")
            ))
            .projectionExpression("connectionId")
            .build());
        String body = "{\"version\":1,\"type\":\"" + event.eventType()
            + "\",\"entityId\":\"" + event.entityId()
            + "\",\"payload\":" + event.payload()
            + ",\"occurredAt\":\"" + event.timestamp() + "\"}";
        for (Map<String, AttributeValue> connection : connections.items()) {
            String connectionId = connection.get("connectionId").s();
            try {
                gateway.postToConnection(PostToConnectionRequest.builder()
                    .connectionId(connectionId)
                    .data(SdkBytes.fromString(body, StandardCharsets.UTF_8))
                    .build());
            } catch (GoneException ignored) {
                removeConnection(userId, connectionId);
            }
        }
    }

    private void removeConnection(String userId, String connectionId) {
        dynamoDb.deleteItem(DeleteItemRequest.builder()
            .tableName(tableName)
            .key(Map.of(
                "PK", AttributeValue.fromS("WSUSER#" + userId),
                "SK", AttributeValue.fromS("CONNECTION#" + connectionId)
            ))
            .build());
        dynamoDb.deleteItem(DeleteItemRequest.builder()
            .tableName(tableName)
            .key(Map.of(
                "PK", AttributeValue.fromS("WSCONNECTION#" + connectionId),
                "SK", AttributeValue.fromS("CONNECTION")
            ))
            .build());
    }
}
