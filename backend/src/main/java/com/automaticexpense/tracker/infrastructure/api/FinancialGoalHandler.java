package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.automaticexpense.tracker.application.FinancialGoalService;
import com.automaticexpense.tracker.application.port.in.FinancialGoalDraft;
import com.automaticexpense.tracker.application.port.in.ManageFinancialGoalUseCase;
import com.automaticexpense.tracker.domain.FinancialGoal;
import com.automaticexpense.tracker.domain.FinancialGoalProjection;
import com.automaticexpense.tracker.domain.GoalAllocation;
import com.automaticexpense.tracker.domain.GoalContribution;
import com.automaticexpense.tracker.domain.GoalContributionCadence;
import com.automaticexpense.tracker.domain.GoalContributionRule;
import com.automaticexpense.tracker.domain.GoalPriority;
import com.automaticexpense.tracker.domain.IntelligenceResult;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbFinancialGoalRepositoryAdapter;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Authenticated HTTP adapter for user-owned goals. The cash-flow implementation supplies the
 * authoritative impact at the application boundary; this route never accepts forecast values from clients.
 */
public final class FinancialGoalHandler
    implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {
    private static final ObjectMapper JSON = new ObjectMapper();
    private final ManageFinancialGoalUseCase configuredService;
    private final GoalServiceFactory configuredFactory;

    public FinancialGoalHandler() {
        configuredService = null;
        configuredFactory = null;
    }

    public FinancialGoalHandler(ManageFinancialGoalUseCase configuredService) {
        this.configuredService = configuredService;
        configuredFactory = null;
    }

    FinancialGoalHandler(GoalServiceFactory configuredFactory) {
        configuredService = null;
        this.configuredFactory = configuredFactory;
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent request, Context context) {
        String principal = AuthenticatedLedgerIdentity.ledgerScope(request);
        if (principal == null) return response(401, "{\"message\":\"Authentication is required\"}");
        String path = request.getRawPath();
        String method = request.getRequestContext().getHttp().getMethod();
        try {
            ManageFinancialGoalUseCase goals = serviceFor(principal);
            if ("GET".equals(method) && "/v2/financial-goals".equals(path)) {
                LocalDate asOf = queryDate(request, "asOf", LocalDate.now());
                return listResponse(goals.list(), goals, asOf);
            }
            if ("POST".equals(method) && "/v2/financial-goals".equals(path)) {
                return goalResponse(201, goals.create(draft(body(request))));
            }
            if ("PUT".equals(method) && goalPath(path)) {
                return goalResponse(200, goals.update(pathId(path, ""), draft(body(request))));
            }
            if ("DELETE".equals(method) && goalPath(path)) {
                goals.delete(pathId(path, ""));
                return response(204, "");
            }
            if ("POST".equals(method) && operationPath(path, "/pause")) {
                return goalResponse(200, goals.pause(pathId(path, "/pause")));
            }
            if ("POST".equals(method) && operationPath(path, "/resume")) {
                return goalResponse(200, goals.resume(pathId(path, "/resume")));
            }
            if ("POST".equals(method) && operationPath(path, "/complete")) {
                return goalResponse(200, goals.complete(pathId(path, "/complete")));
            }
            if ("POST".equals(method) && operationPath(path, "/contributions")) {
                return goalResponse(200, goals.recordContribution(
                    pathId(path, "/contributions"), contribution(body(request))
                ));
            }
            if ("GET".equals(method) && operationPath(path, "/projection")) {
                return projectionResponse(goals.project(
                    pathId(path, "/projection"), queryDate(request, "asOf", LocalDate.now()), null
                ));
            }
            return response(404, "{\"message\":\"Route not found\"}");
        } catch (IllegalArgumentException | IllegalStateException exception) {
            return response(400, "{\"message\":\"Invalid financial goal request\"}");
        } catch (JsonProcessingException exception) {
            return response(400, "{\"message\":\"Invalid JSON request body\"}");
        } catch (SdkException exception) {
            return response(503, "{\"message\":\"Financial goal service is unavailable\"}");
        }
    }

    private ManageFinancialGoalUseCase serviceFor(String principal) {
        if (configuredService != null) return configuredService;
        if (configuredFactory != null) return configuredFactory.create(principal);
        return new FinancialGoalService(new AwsDynamoDbFinancialGoalRepositoryAdapter(
            DynamoDbClient.create(), requiredEnvironment("TABLE_NAME"), principal
        ));
    }

    private APIGatewayV2HTTPResponse listResponse(
        List<FinancialGoal> stored, ManageFinancialGoalUseCase goals, LocalDate asOf
    ) throws JsonProcessingException {
        List<Map<String, Object>> items = new ArrayList<>();
        for (FinancialGoal goal : stored) {
            Map<String, Object> item = new LinkedHashMap<>(goalPayload(goal));
            item.put("projection", projectionPayload(goals.project(goal.id(), asOf, null)));
            items.add(item);
        }
        return response(200, JSON.writeValueAsString(Map.of("asOf", asOf.toString(), "goals", items)));
    }

    private APIGatewayV2HTTPResponse goalResponse(int status, FinancialGoal goal) throws JsonProcessingException {
        return response(status, JSON.writeValueAsString(goalPayload(goal)));
    }

    private APIGatewayV2HTTPResponse projectionResponse(IntelligenceResult<FinancialGoalProjection> projection)
        throws JsonProcessingException {
        return response(200, JSON.writeValueAsString(projectionPayload(projection)));
    }

    private Map<String, Object> goalPayload(FinancialGoal goal) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("id", goal.id());
        payload.put("name", goal.name());
        payload.put("targetAmount", goal.targetAmount().amount().toPlainString());
        payload.put("currency", goal.targetAmount().currency());
        payload.put("targetDate", goal.targetDate().toString());
        payload.put("priority", goal.priority().name());
        payload.put("lifecycle", goal.lifecycle().name());
        payload.put("allocations", goal.allocations().stream().map(allocation -> {
            Map<String, Object> value = new LinkedHashMap<>();
            value.put("reference", allocation.reference());
            value.put("amount", allocation.amount().amount().toPlainString());
            value.put("linkedAccountId", allocation.linkedAccountId());
            return value;
        }).toList());
        payload.put("contributionRule", goal.contributionRule().isConfigured() ? Map.of(
            "amount", goal.contributionRule().amount().amount().toPlainString(),
            "cadence", goal.contributionRule().cadence().name()
        ) : null);
        payload.put("contributions", goal.contributions().stream().map(contribution -> {
            Map<String, Object> value = new LinkedHashMap<>();
            value.put("id", contribution.id());
            value.put("amount", contribution.amount().amount().toPlainString());
            value.put("contributedOn", contribution.contributedOn().toString());
            value.put("evidenceReference", contribution.evidenceReference());
            return value;
        }).toList());
        return payload;
    }

    private Map<String, Object> projectionPayload(IntelligenceResult<FinancialGoalProjection> result) {
        FinancialGoalProjection projection = result.value();
        Map<String, Object> value = new LinkedHashMap<>();
        value.put("amountRemaining", projection.amountRemaining().amount().toPlainString());
        value.put("currency", projection.amountRemaining().currency());
        value.put("monthsRemaining", projection.monthsRemaining());
        value.put("requiredMonthlyContribution", projection.requiredMonthlyContribution().amount().toPlainString());
        value.put("observedMonthlyContribution", projection.observedMonthlyContribution().amount().toPlainString());
        value.put("projectedCompletionDate",
            projection.projectedCompletionDate() == null ? null : projection.projectedCompletionDate().toString());
        value.put("monthlyShortfallOrSurplus", projection.monthlyShortfallOrSurplus().amount().toPlainString());
        value.put("minimumBalanceBreached", projection.minimumBalanceBreached());
        value.put("status", projection.status().name());
        value.put("contributionEvidenceReferences", projection.contributionEvidenceReferences());

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("classification", result.classification().name());
        payload.put("asOf", result.asOf().toString());
        payload.put("freshnessAsOf", result.freshnessAsOf().toString());
        payload.put("formula", Map.of("id", result.formula().id(), "version", result.formula().version()));
        payload.put("confidence", result.confidence().toPlainString());
        payload.put("sourceCount", result.evidence().sourceCount());
        payload.put("assumptions", result.assumptions());
        payload.put("warnings", result.warnings().stream().map(Enum::name).toList());
        payload.put("filters", Map.of("goalId", "provided in route"));
        payload.put("comparisonBaseline", null);
        payload.put("value", value);
        return payload;
    }

    private FinancialGoalDraft draft(JsonNode body) {
        String currency = requiredText(body, "currency");
        JsonNode rule = body.path("contributionRule");
        GoalContributionRule contributionRule = rule.isMissingNode() || rule.isNull()
            ? GoalContributionRule.none()
            : new GoalContributionRule(
                Money.of(requiredText(rule, "amount"), currency),
                GoalContributionCadence.valueOf(requiredText(rule, "cadence"))
            );
        return new FinancialGoalDraft(
            requiredText(body, "name"),
            Money.of(requiredText(body, "targetAmount"), currency),
            LocalDate.parse(requiredText(body, "targetDate")),
            allocations(body, currency),
            GoalPriority.valueOf(requiredText(body, "priority")),
            contributionRule
        );
    }

    private List<GoalAllocation> allocations(JsonNode body, String currency) {
        JsonNode values = body.path("allocations");
        if (!values.isArray()) throw new IllegalArgumentException("allocations must be an array");
        List<GoalAllocation> allocations = new ArrayList<>();
        for (JsonNode value : values) {
            String linkedAccountId = value.path("linkedAccountId").asText(null);
            allocations.add(new GoalAllocation(
                requiredText(value, "reference"),
                Money.of(requiredText(value, "amount"), currency),
                linkedAccountId == null || linkedAccountId.isBlank() ? null : linkedAccountId
            ));
        }
        return List.copyOf(allocations);
    }

    private GoalContribution contribution(JsonNode body) {
        return new GoalContribution(
            requiredText(body, "id"),
            Money.of(requiredText(body, "amount"), requiredText(body, "currency")),
            LocalDate.parse(requiredText(body, "contributedOn")),
            optionalText(body, "evidenceReference")
        );
    }

    private JsonNode body(APIGatewayV2HTTPEvent request) throws JsonProcessingException {
        JsonNode parsed = JSON.readTree(request.getBody());
        if (parsed == null || parsed.isNull()) throw new IllegalArgumentException("Request body is required");
        return parsed;
    }

    private boolean goalPath(String path) {
        return path != null && path.matches("/v2/financial-goals/[^/]+");
    }

    private boolean operationPath(String path, String operation) {
        return path != null && path.matches("/v2/financial-goals/[^/]+" + operation);
    }

    private String pathId(String path, String suffix) {
        return path.substring("/v2/financial-goals/".length(), path.length() - suffix.length());
    }

    private String requiredText(JsonNode body, String field) {
        String value = body.path(field).asText(null);
        if (value == null || value.isBlank()) throw new IllegalArgumentException(field + " is required");
        return value;
    }

    private String optionalText(JsonNode body, String field) {
        String value = body.path(field).asText(null);
        return value == null || value.isBlank() ? null : value;
    }

    private LocalDate queryDate(APIGatewayV2HTTPEvent request, String name, LocalDate defaultValue) {
        String value = request.getQueryStringParameters() == null ? null : request.getQueryStringParameters().get(name);
        return value == null || value.isBlank() ? defaultValue : LocalDate.parse(value);
    }

    private String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) throw new IllegalStateException(name + " is not configured");
        return value;
    }

    private APIGatewayV2HTTPResponse response(int status, String body) {
        return APIGatewayV2HTTPResponse.builder()
            .withStatusCode(status)
            .withHeaders(Map.of("Content-Type", "application/json"))
            .withBody(body)
            .build();
    }

    @FunctionalInterface
    interface GoalServiceFactory {
        ManageFinancialGoalUseCase create(String principal);
    }
}
