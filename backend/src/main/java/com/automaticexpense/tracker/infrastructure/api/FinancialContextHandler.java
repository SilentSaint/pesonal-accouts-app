package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.automaticexpense.tracker.application.FinancialContextService;
import com.automaticexpense.tracker.application.port.in.CreateFinancialContextItemRequest;
import com.automaticexpense.tracker.application.port.in.EligibleFinancialContextFields;
import com.automaticexpense.tracker.application.port.in.FinancialContextItemView;
import com.automaticexpense.tracker.application.port.in.FinancialContextListView;
import com.automaticexpense.tracker.application.port.in.ManageFinancialContextUseCase;
import com.automaticexpense.tracker.application.port.in.UpdateFinancialContextItemRequest;
import com.automaticexpense.tracker.domain.ContextProvenance;
import com.automaticexpense.tracker.domain.FinancialContextCapability;
import com.automaticexpense.tracker.domain.FinancialContextItem;
import com.automaticexpense.tracker.domain.FinancialContextType;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbFinancialContextRepositoryAdapter;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Authenticated HTTP adapter for explicit user-owned financial context.
 * API Gateway verifies the JWT; this adapter derives its partition from the verified email using
 * the same ledger scope as canonical transactions.
 */
public final class FinancialContextHandler
    implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {
    private static final ObjectMapper JSON = new ObjectMapper();
    private final ManageFinancialContextUseCase configuredService;

    public FinancialContextHandler() {
        this.configuredService = null;
    }

    public FinancialContextHandler(ManageFinancialContextUseCase configuredService) {
        this.configuredService = configuredService;
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent request, Context context) {
        String principal = AuthenticatedLedgerIdentity.ledgerScope(request);
        if (principal == null) {
            return response(401, "{\"message\":\"Authentication is required\"}");
        }

        String path = request.getRawPath();
        String method = request.getRequestContext().getHttp().getMethod();
        try {
            ManageFinancialContextUseCase service = serviceFor(principal);
            if ("GET".equals(method) && "/v2/financial-context".equals(path)) {
                return listResponse(service.list(asOf(request)));
            }
            if ("GET".equals(method) && "/v2/financial-context/eligible".equals(path)) {
                String capability = query(request, "capability");
                if (capability == null) {
                    throw new IllegalArgumentException("capability is required");
                }
                return eligibleResponse(
                    asOf(request), FinancialContextCapability.valueOf(capability),
                    service.selectEligibleFields(FinancialContextCapability.valueOf(capability), asOf(request))
                );
            }
            if ("POST".equals(method) && "/v2/financial-context".equals(path)) {
                return itemResponse(201, service.create(createRequest(body(request))));
            }
            if ("PUT".equals(method) && contextItemPath(path)) {
                return itemResponse(200, service.update(pathId(path), updateRequest(body(request))));
            }
            if ("POST".equals(method) && deactivatePath(path)) {
                return itemResponse(200, service.deactivate(pathId(path.substring(0, path.length() - "/deactivate".length()))));
            }
            if ("DELETE".equals(method) && contextItemPath(path)) {
                service.delete(pathId(path));
                return response(204, "");
            }
            return response(404, "{\"message\":\"Route not found\"}");
        } catch (IllegalArgumentException | DateTimeParseException exception) {
            return response(400, "{\"message\":\"Invalid financial context request\"}");
        } catch (JsonProcessingException exception) {
            return response(400, "{\"message\":\"Invalid JSON request body\"}");
        } catch (SdkException exception) {
            return response(503, "{\"message\":\"Financial context service is unavailable\"}");
        }
    }

    private ManageFinancialContextUseCase serviceFor(String principal) {
        if (configuredService != null) {
            return configuredService;
        }
        return new FinancialContextService(new AwsDynamoDbFinancialContextRepositoryAdapter(
            DynamoDbClient.create(), requiredEnvironment("TABLE_NAME"), principal
        ));
    }

    private CreateFinancialContextItemRequest createRequest(JsonNode body) {
        return new CreateFinancialContextItemRequest(
            FinancialContextType.valueOf(requiredText(body, "type")),
            requiredText(body, "label"),
            values(body),
            capabilities(body),
            ContextProvenance.valueOf(body.path("provenance").asText(ContextProvenance.USER_DECLARED.name())),
            date(body, "effectiveFrom"),
            date(body, "effectiveUntil")
        );
    }

    private UpdateFinancialContextItemRequest updateRequest(JsonNode body) {
        return new UpdateFinancialContextItemRequest(
            requiredText(body, "label"), values(body), capabilities(body),
            date(body, "effectiveFrom"), date(body, "effectiveUntil")
        );
    }

    private JsonNode body(APIGatewayV2HTTPEvent request) throws JsonProcessingException {
        JsonNode body = JSON.readTree(request.getBody());
        if (body == null || body.isNull()) {
            throw new IllegalArgumentException("Request body is required");
        }
        return body;
    }

    private Map<String, String> values(JsonNode body) {
        JsonNode values = body.path("values");
        if (!values.isObject()) {
            throw new IllegalArgumentException("values is required");
        }
        Map<String, String> result = new LinkedHashMap<>();
        values.fields().forEachRemaining(entry -> {
            if (!entry.getValue().isTextual()) {
                throw new IllegalArgumentException("values must contain text values");
            }
            result.put(entry.getKey(), entry.getValue().asText());
        });
        return result;
    }

    private Set<FinancialContextCapability> capabilities(JsonNode body) {
        JsonNode capabilities = body.path("capabilities");
        if (!capabilities.isArray() || capabilities.isEmpty()) {
            throw new IllegalArgumentException("capabilities is required");
        }
        java.util.LinkedHashSet<FinancialContextCapability> result = new java.util.LinkedHashSet<>();
        capabilities.forEach(value -> result.add(FinancialContextCapability.valueOf(value.asText())));
        return Set.copyOf(result);
    }

    private LocalDate date(JsonNode body, String field) {
        String value = nullableText(body, field);
        return value == null ? null : LocalDate.parse(value);
    }

    private Instant asOf(APIGatewayV2HTTPEvent request) {
        String value = query(request, "asOf");
        return value == null ? Instant.now() : Instant.parse(value);
    }

    private APIGatewayV2HTTPResponse listResponse(FinancialContextListView view) throws JsonProcessingException {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("asOf", view.asOf().toString());
        payload.put("items", view.items().stream().map(this::itemViewPayload).toList());
        return response(200, JSON.writeValueAsString(payload));
    }

    private APIGatewayV2HTTPResponse eligibleResponse(
        Instant asOf, FinancialContextCapability capability, List<EligibleFinancialContextFields> items
    ) throws JsonProcessingException {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("asOf", asOf.toString());
        payload.put("capability", capability.name());
        payload.put("items", items.stream().map(item -> Map.of(
            "id", item.itemId(), "type", item.type().name(), "fields", item.fields()
        )).toList());
        return response(200, JSON.writeValueAsString(payload));
    }

    private APIGatewayV2HTTPResponse itemResponse(int status, FinancialContextItem item) throws JsonProcessingException {
        return response(status, JSON.writeValueAsString(itemPayload(item)));
    }

    private Map<String, Object> itemViewPayload(FinancialContextItemView view) {
        Map<String, Object> payload = itemPayload(view.item());
        payload.put("status", view.status().name());
        payload.put("conflictIds", view.conflictIds());
        return payload;
    }

    private Map<String, Object> itemPayload(FinancialContextItem item) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("id", item.id());
        payload.put("type", item.type().name());
        payload.put("label", item.label());
        payload.put("values", item.values());
        payload.put("capabilities", item.capabilities().stream().map(Enum::name).sorted().toList());
        payload.put("provenance", item.provenance().name());
        payload.put("effectiveFrom", item.effectiveFrom() == null ? null : item.effectiveFrom().toString());
        payload.put("effectiveUntil", item.effectiveUntil() == null ? null : item.effectiveUntil().toString());
        payload.put("active", item.active());
        payload.put("createdAt", item.createdAt().toString());
        payload.put("updatedAt", item.updatedAt().toString());
        return payload;
    }

    private boolean contextItemPath(String path) {
        return path != null && path.matches("/v2/financial-context/[^/]+");
    }

    private boolean deactivatePath(String path) {
        return path != null && path.matches("/v2/financial-context/[^/]+/deactivate");
    }

    private String pathId(String path) {
        return path.substring("/v2/financial-context/".length());
    }

    private String query(APIGatewayV2HTTPEvent request, String name) {
        return request.getQueryStringParameters() == null ? null : request.getQueryStringParameters().get(name);
    }

    private String requiredText(JsonNode body, String field) {
        String value = nullableText(body, field);
        if (value == null) {
            throw new IllegalArgumentException(field + " is required");
        }
        return value;
    }

    private String nullableText(JsonNode body, String field) {
        String value = body.path(field).asText(null);
        return value == null || value.isBlank() ? null : value;
    }

    private String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(name + " is not configured");
        }
        return value;
    }

    private APIGatewayV2HTTPResponse response(int statusCode, String body) {
        return APIGatewayV2HTTPResponse.builder()
            .withStatusCode(statusCode)
            .withHeaders(Map.of("Content-Type", "application/json"))
            .withBody(body)
            .build();
    }
}
