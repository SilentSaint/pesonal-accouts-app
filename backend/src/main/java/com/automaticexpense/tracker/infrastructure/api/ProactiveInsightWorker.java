package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.automaticexpense.tracker.application.RefreshFinancialProjectionsService;
import com.automaticexpense.tracker.application.port.in.RefreshFinancialProjectionsRequest;
import com.automaticexpense.tracker.application.port.in.RefreshFinancialProjectionsUseCase;
import com.automaticexpense.tracker.domain.ProactiveInsightCalculator;
import com.automaticexpense.tracker.infrastructure.messaging.AwsApiGatewayWebSocketEventPublisher;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbProactiveInsightRepositoryAdapter;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.services.apigatewaymanagementapi.ApiGatewayManagementApiClient;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.time.Instant;
import java.time.ZoneId;
import java.util.Objects;

/**
 * Idempotent SQS consumer; card persistence is conditioned on each stable deduplication key.
 */
public final class ProactiveInsightWorker implements RequestHandler<SQSEvent, Void> {
    private static final ObjectMapper JSON = new ObjectMapper();
    private final RefreshFinancialProjectionsUseCase refresh;

    public ProactiveInsightWorker() {
        this(defaultService());
    }

    public ProactiveInsightWorker(RefreshFinancialProjectionsUseCase refresh) {
        this.refresh = Objects.requireNonNull(refresh, "refresh cannot be null");
    }

    @Override
    public Void handleRequest(SQSEvent event, Context context) {
        if (event == null || event.getRecords() == null) {
            throw new IllegalArgumentException("SQS event records are required");
        }
        for (SQSEvent.SQSMessage message : event.getRecords()) {
            refresh.refresh(parse(message.getBody()));
        }
        return null;
    }

    private RefreshFinancialProjectionsRequest parse(String body) {
        try {
            Message message = JSON.readValue(body, Message.class);
            return new RefreshFinancialProjectionsRequest(
                message.userId(), Instant.parse(message.asOf()), ZoneId.of(message.timezone()), message.currency()
            );
        } catch (Exception exception) {
            throw new IllegalArgumentException("Insight refresh message is invalid", exception);
        }
    }

    private static RefreshFinancialProjectionsUseCase defaultService() {
        DynamoDbClient dynamo = DynamoDbClient.create();
        String table = requiredEnvironment("TABLE_NAME");
        AwsDynamoDbProactiveInsightRepositoryAdapter repository =
            new AwsDynamoDbProactiveInsightRepositoryAdapter(dynamo, table);
        return new RefreshFinancialProjectionsService(repository, repository, new ProactiveInsightCalculator(),
            new AwsApiGatewayWebSocketEventPublisher(dynamo, ApiGatewayManagementApiClient.builder()
                .endpointOverride(java.net.URI.create(requiredEnvironment("WEBSOCKET_MANAGEMENT_ENDPOINT"))).build(), table));
    }

    private static String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) throw new IllegalStateException(name + " is not configured");
        return value;
    }

    private record Message(String userId, String asOf, String timezone, String currency) {}
}
