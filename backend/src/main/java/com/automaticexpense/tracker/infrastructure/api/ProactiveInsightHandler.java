package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.automaticexpense.tracker.application.RefreshFinancialProjectionsService;
import com.automaticexpense.tracker.application.port.in.ManageProactiveInsightsUseCase;
import com.automaticexpense.tracker.domain.*;
import com.automaticexpense.tracker.infrastructure.messaging.AwsApiGatewayWebSocketEventPublisher;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbProactiveInsightRepositoryAdapter;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.services.apigatewaymanagementapi.ApiGatewayManagementApiClient;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Authenticated HTTP adapter for persisted proactive insight cards.
 */
public final class ProactiveInsightHandler
    implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {
    private static final ObjectMapper JSON = new ObjectMapper();
    private final ManageProactiveInsightsUseCase insights;

    public ProactiveInsightHandler() {
        this.insights = null;
    }

    public ProactiveInsightHandler(ManageProactiveInsightsUseCase insights) {
        this.insights = insights;
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent request, Context context) {
        String email = authenticatedEmail(request);
        if (email == null) return response(401, Map.of("message", "Authentication is required"));
        String userId = scopeId(email);
        String path = request.getRawPath();
        String method = request.getRequestContext() == null || request.getRequestContext().getHttp() == null
            ? "" : request.getRequestContext().getHttp().getMethod();
        try {
            if ("GET".equals(method) && "/v2/insights".equals(path)) {
                boolean includeDismissed = request.getQueryStringParameters() != null
                    && "true".equalsIgnoreCase(request.getQueryStringParameters().get("includeDismissed"));
                return response(200, Map.of("items", service().list(userId, Instant.now(), includeDismissed)));
            }
            String prefix = "/v2/insights/";
            if ("POST".equals(method) && path.startsWith(prefix) && path.endsWith("/dismiss")) {
                String id = path.substring(prefix.length(), path.length() - "/dismiss".length());
                if (id.isBlank() || id.contains("/")) return response(404, Map.of("message", "Route not found"));
                service().dismiss(userId, id);
                return APIGatewayV2HTTPResponse.builder().withStatusCode(204).build();
            }
            return response(404, Map.of("message", "Route not found"));
        } catch (IllegalArgumentException exception) {
            return response(400, Map.of("message", exception.getMessage()));
        }
    }

    private ManageProactiveInsightsUseCase service() {
        if (insights != null) return insights;
        DynamoDbClient dynamo = DynamoDbClient.create();
        String table = requiredEnvironment("TABLE_NAME");
        AwsDynamoDbProactiveInsightRepositoryAdapter repository =
            new AwsDynamoDbProactiveInsightRepositoryAdapter(dynamo, table);
        return new RefreshFinancialProjectionsService(repository, repository, new ProactiveInsightCalculator(),
            new AwsApiGatewayWebSocketEventPublisher(dynamo, ApiGatewayManagementApiClient.builder()
                .endpointOverride(java.net.URI.create(requiredEnvironment("WEBSOCKET_MANAGEMENT_ENDPOINT"))).build(), table));
    }

    private Map<String, Object> card(ProactiveInsight insight) {
        Map<String, Object> card = new LinkedHashMap<>();
        card.put("id", insight.id());
        card.put("type", insight.type().name());
        card.put("classification", insight.classification().name());
        card.put("title", insight.title());
        card.put("message", insight.message());
        card.put("currentAmount", money(insight.currentAmount()));
        card.put("comparisonBaseline", Map.of("amount", money(insight.baselineAmount()), "label", insight.baselineLabel()));
        card.put("baselineLabel", insight.baselineLabel());
        card.put("confidence", insight.confidence());
        card.put("asOf", insight.asOf().toString());
        card.put("freshnessAsOf", insight.freshnessAsOf().toString());
        card.put("formula", Map.of("id", insight.formula().id(), "version", insight.formula().version()));
        card.put("sourceCount", insight.evidence().sourceCount());
        card.put("filters", filters(insight.evidence().drillDown()));
        card.put("matchingTransactions", insight.matchingTransactions().stream().map(transaction -> Map.of(
            "transactionId", transaction.transactionId(), "timestamp", transaction.timestamp().toString(),
            "merchantName", transaction.merchantName(), "personalSpend", money(transaction.personalSpend())
        )).toList());
        card.put("assumptions", insight.assumptions());
        card.put("warnings", insight.warnings().stream().map(Enum::name).toList());
        card.put("lifecycleState", insight.lifecycleState().name());
        card.put("expiresAt", insight.expiresAt().toString());
        return card;
    }

    private Map<String, Object> filters(DrillDownReference reference) {
        return Map.of(
            "start", reference.period().start().toString(), "end", reference.period().end().toString(),
            "currency", reference.currency(), "categoryId", reference.categoryId() == null ? "" : reference.categoryId(),
            "merchantName", reference.merchantName() == null ? "" : reference.merchantName()
        );
    }

    private Map<String, Object> money(Money money) {
        return Map.of("amount", money.amount(), "currency", money.currency());
    }

    private APIGatewayV2HTTPResponse response(int status, Map<String, ?> payload) {
        try {
            if (payload.containsKey("items") && payload.get("items") instanceof List<?> values) {
                payload = Map.of("items", values.stream().map(value -> card((ProactiveInsight) value)).toList());
            }
            return APIGatewayV2HTTPResponse.builder().withStatusCode(status)
                .withHeaders(Map.of("Content-Type", "application/json"))
                .withBody(JSON.writeValueAsString(payload)).build();
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to serialize proactive insights", exception);
        }
    }

    private String authenticatedEmail(APIGatewayV2HTTPEvent request) {
        if (request == null || request.getRequestContext() == null || request.getRequestContext().getAuthorizer() == null
            || request.getRequestContext().getAuthorizer().getJwt() == null
            || request.getRequestContext().getAuthorizer().getJwt().getClaims() == null) return null;
        Map<String, String> claims = request.getRequestContext().getAuthorizer().getJwt().getClaims();
        return "true".equalsIgnoreCase(claims.get("email_verified")) ? claims.get("email") : null;
    }

    private String scopeId(String email) {
        try {
            return java.util.HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(email.toLowerCase().trim().getBytes(StandardCharsets.UTF_8))).substring(0, 32);
        } catch (java.security.NoSuchAlgorithmException exception) {
            throw new IllegalStateException("Unable to derive authenticated user scope", exception);
        }
    }

    private String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) throw new IllegalStateException(name + " is not configured");
        return value;
    }
}
