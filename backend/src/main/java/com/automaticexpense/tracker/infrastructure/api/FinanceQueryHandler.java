package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.automaticexpense.tracker.application.FinanceAnswerComposerService;
import com.automaticexpense.tracker.application.FinanceQueryAliasRegistry;
import com.automaticexpense.tracker.application.FinanceQueryPlannerService;
import com.automaticexpense.tracker.application.FinancialCapabilityService;
import com.automaticexpense.tracker.application.FinancialSnapshotService;
import com.automaticexpense.tracker.application.port.in.ComposeFinanceAnswerUseCase;
import com.automaticexpense.tracker.application.port.in.EvaluateFinancialCapabilityUseCase;
import com.automaticexpense.tracker.application.port.in.LoadFinancialSnapshotUseCase;
import com.automaticexpense.tracker.application.port.in.PlanFinanceQueryUseCase;
import com.automaticexpense.tracker.domain.DrillDownReference;
import com.automaticexpense.tracker.domain.FinanceAnswer;
import com.automaticexpense.tracker.domain.FinanceQuery;
import com.automaticexpense.tracker.domain.FinanceQueryClarification;
import com.automaticexpense.tracker.domain.FinanceQueryPlanningResult;
import com.automaticexpense.tracker.domain.FinancialSnapshot;
import com.automaticexpense.tracker.domain.FinancialSnapshotRequest;
import com.automaticexpense.tracker.domain.IntelligenceResult;
import com.automaticexpense.tracker.domain.PlannedFinanceQuery;
import com.automaticexpense.tracker.domain.SpendingAnalytics;
import com.automaticexpense.tracker.domain.SpendingAnalyticsCalculator;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbFinancialSnapshotRepositoryAdapter;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.time.Instant;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * HTTP adapter for deterministic conversational spending queries.
 * Paid model planning remains disabled until an injected Secrets Manager credential adapter is configured.
 */
public final class FinanceQueryHandler
    implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {

    private static final ObjectMapper JSON = new ObjectMapper();

    private final LoadFinancialSnapshotUseCase snapshots;
    private final PlanFinanceQueryUseCase planner;
    private final EvaluateFinancialCapabilityUseCase capabilities;
    private final ComposeFinanceAnswerUseCase composer;
    private final FinanceQueryAliasRegistry aliases;

    public FinanceQueryHandler() {
        snapshots = null;
        planner = null;
        capabilities = null;
        composer = null;
        aliases = new FinanceQueryAliasRegistry();
    }

    public FinanceQueryHandler(
        LoadFinancialSnapshotUseCase snapshots,
        PlanFinanceQueryUseCase planner,
        EvaluateFinancialCapabilityUseCase capabilities,
        ComposeFinanceAnswerUseCase composer,
        FinanceQueryAliasRegistry aliases
    ) {
        this.snapshots = snapshots;
        this.planner = planner;
        this.capabilities = capabilities;
        this.composer = composer;
        this.aliases = aliases;
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent request, Context context) {
        if (!"POST".equals(request.getRequestContext().getHttp().getMethod())
            || !"/v2/finance-queries".equals(request.getRawPath())) {
            return response(404, Map.of("message", "Route not found"));
        }
        String principal = authenticatedEmail(request);
        if (principal == null) {
            return response(401, Map.of("message", "Authentication is required"));
        }
        try {
            FinanceQuery query = query(request.getBody());
            IntelligenceResult<FinancialSnapshot> snapshot = snapshots(principal).load(
                new FinancialSnapshotRequest(query.asOf(), query.timezone(), java.util.Set.of(), query.currency())
            );
            FinanceQueryPlanningResult planning = planner().plan(query, aliases.register(snapshot.value()));
            if (planning instanceof FinanceQueryClarification clarification) {
                return response(200, Map.of("status", "CLARIFICATION", "message", clarification.message()));
            }
            PlannedFinanceQuery planned = (PlannedFinanceQuery) planning;
            IntelligenceResult<SpendingAnalytics> evaluated = capabilities().evaluate(
                snapshot.value(), planned.plan().filters().asAnalyticsRequest()
            );
            FinanceAnswer answer = composer().compose(planned.plan(), evaluated);
            return response(200, answerEnvelope(answer, planned.usedHostedModel()));
        } catch (IllegalArgumentException exception) {
            return response(400, Map.of("message", exception.getMessage()));
        } catch (SdkException exception) {
            return response(503, Map.of("message", "Financial query service is unavailable"));
        }
    }

    private LoadFinancialSnapshotUseCase snapshots(String principal) {
        if (snapshots != null) {
            return snapshots;
        }
        return new FinancialSnapshotService(new AwsDynamoDbFinancialSnapshotRepositoryAdapter(
            DynamoDbClient.create(), requiredEnvironment("TABLE_NAME"), userScopeId(principal)
        ));
    }

    private PlanFinanceQueryUseCase planner() {
        return planner == null ? new FinanceQueryPlannerService() : planner;
    }

    private EvaluateFinancialCapabilityUseCase capabilities() {
        return capabilities == null
            ? new FinancialCapabilityService(new SpendingAnalyticsCalculator()) : capabilities;
    }

    private ComposeFinanceAnswerUseCase composer() {
        return composer == null ? new FinanceAnswerComposerService() : composer;
    }

    private FinanceQuery query(String body) {
        try {
            JsonNode value = JSON.readTree(body == null ? "" : body);
            if (value == null || !value.isObject()) {
                throw new IllegalArgumentException("request body must be a JSON object");
            }
            String question = requiredText(value, "question");
            String currency = value.path("currency").asText("INR");
            ZoneId timezone = ZoneId.of(value.path("timezone").asText("Asia/Kolkata"));
            Instant asOf = value.has("asOf") ? Instant.parse(requiredText(value, "asOf")) : Instant.now();
            return new FinanceQuery(question, asOf, timezone, currency);
        } catch (JsonProcessingException exception) {
            throw new IllegalArgumentException("request body must be valid JSON");
        } catch (java.time.DateTimeException exception) {
            throw new IllegalArgumentException("asOf and timezone must be valid ISO-8601 and IANA values");
        }
    }

    private String requiredText(JsonNode value, String field) {
        if (!value.path(field).isTextual() || value.path(field).textValue().isBlank()) {
            throw new IllegalArgumentException(field + " must be a non-blank string");
        }
        return value.path(field).textValue();
    }

    private Map<String, Object> answerEnvelope(FinanceAnswer answer, boolean usedHostedModel) {
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("status", "ANSWER");
        envelope.put("classification", answer.classification().name());
        envelope.put("observation", answer.observation());
        envelope.put("asOf", answer.asOf().toString());
        envelope.put("formula", Map.of("id", answer.formula().id(), "version", answer.formula().version()));
        envelope.put("sourceCount", answer.evidence().sourceCount());
        envelope.put("assumptions", answer.assumptions());
        envelope.put("warnings", answer.warnings().stream().map(Enum::name).toList());
        envelope.put("usedHostedModel", usedHostedModel);
        if (answer.evidence().drillDown() != null) {
            envelope.put("drillDown", drillDown(answer.evidence().drillDown()));
        }
        return envelope;
    }

    private Map<String, Object> drillDown(DrillDownReference reference) {
        return Map.of(
            "start", reference.period().start().toString(),
            "end", reference.period().end().toString(),
            "currency", reference.currency(),
            "accountIds", reference.accountIds().stream().map(account -> account.value()).sorted().toList(),
            "categoryId", reference.categoryId() == null ? "" : reference.categoryId(),
            "merchantName", reference.merchantName() == null ? "" : reference.merchantName()
        );
    }

    private APIGatewayV2HTTPResponse response(int status, Map<String, ?> payload) {
        try {
            return APIGatewayV2HTTPResponse.builder()
                .withStatusCode(status)
                .withHeaders(Map.of("Content-Type", "application/json"))
                .withBody(JSON.writeValueAsString(payload))
                .build();
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to serialize finance query response", exception);
        }
    }

    private String authenticatedEmail(APIGatewayV2HTTPEvent request) {
        if (request.getRequestContext() == null
            || request.getRequestContext().getAuthorizer() == null
            || request.getRequestContext().getAuthorizer().getJwt() == null
            || request.getRequestContext().getAuthorizer().getJwt().getClaims() == null) {
            return null;
        }
        Map<String, String> claims = request.getRequestContext().getAuthorizer().getJwt().getClaims();
        return "true".equalsIgnoreCase(claims.get("email_verified")) ? claims.get("email") : null;
    }

    private String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(name + " is not configured");
        }
        return value;
    }

    private String userScopeId(String email) {
        try {
            byte[] bytes = java.security.MessageDigest.getInstance("SHA-256")
                .digest(email.toLowerCase().trim().getBytes(java.nio.charset.StandardCharsets.UTF_8));
            return java.util.HexFormat.of().formatHex(bytes).substring(0, 32);
        } catch (java.security.NoSuchAlgorithmException exception) {
            throw new IllegalStateException("Unable to derive authenticated user scope", exception);
        }
    }
}
