package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.automaticexpense.tracker.application.IncomeSourceService;
import com.automaticexpense.tracker.application.port.in.ManageIncomeSourceUseCase;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IncomeCadence;
import com.automaticexpense.tracker.domain.IncomeSource;
import com.automaticexpense.tracker.domain.IncomeSourceType;
import com.automaticexpense.tracker.domain.IncomeSuggestion;
import com.automaticexpense.tracker.domain.IncomeSummary;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbAccountTransactionRepositoryAdapter;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbIncomeSourceRepositoryAdapter;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Authenticated income management adapter. DynamoDB partitions are always derived from API
 * Gateway's verified JWT subject, never from request input.
 */
public final class IncomeSourceHandler
    implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {
    private static final ObjectMapper JSON = new ObjectMapper();
    private final ManageIncomeSourceUseCase configuredService;
    private final IncomeServiceFactory configuredFactory;

    public IncomeSourceHandler() {
        configuredService = null;
        configuredFactory = null;
    }

    public IncomeSourceHandler(ManageIncomeSourceUseCase configuredService) {
        this.configuredService = configuredService;
        configuredFactory = null;
    }

    IncomeSourceHandler(IncomeServiceFactory configuredFactory) {
        this.configuredService = null;
        this.configuredFactory = configuredFactory;
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent request, Context context) {
        String ledgerScope = AuthenticatedLedgerIdentity.ledgerScope(request);
        if (ledgerScope == null) {
            return response(401, "{\"message\":\"Authentication is required\"}");
        }
        String path = request.getRawPath();
        String method = request.getRequestContext().getHttp().getMethod();
        try {
            ManageIncomeSourceUseCase service = serviceFor(ledgerScope);
            if ("GET".equals(method) && "/v2/income-sources".equals(path)) {
                service.detectIncomeSuggestions();
                return sourcesResponse(service.getConfirmedIncomeSources(), service.getUnconfirmedSuggestions());
            }
            if ("POST".equals(method) && "/v2/income-sources".equals(path)) {
                return sourceResponse(201, service.createIncomeSource(
                    requiredText(body(request), "name"),
                    IncomeSourceType.valueOf(requiredText(body(request), "type")),
                    Money.of(requiredText(body(request), "amount"), requiredText(body(request), "currency")),
                    IncomeCadence.valueOf(requiredText(body(request), "cadence")),
                    LocalDate.parse(requiredText(body(request), "effectiveFrom")),
                    optionalDate(body(request), "effectiveTo"),
                    new AccountId(requiredText(body(request), "linkedAccountId")),
                    transactionIds(body(request))
                ));
            }
            if ("PUT".equals(method) && effectiveDatesPath(path)) {
                JsonNode body = body(request);
                return sourceResponse(200, service.updateEffectiveDates(
                    pathId(path, "/effective-dates"),
                    LocalDate.parse(requiredText(body, "effectiveFrom")),
                    optionalDate(body, "effectiveTo")
                ));
            }
            if ("POST".equals(method) && confirmationPath(path, "/confirm")) {
                return sourceResponse(200, service.confirmSuggestion(pathId(path, "/confirm")));
            }
            if ("POST".equals(method) && confirmationPath(path, "/reject")) {
                return sourceResponse(200, service.rejectSuggestion(pathId(path, "/reject")));
            }
            if ("GET".equals(method) && "/v2/income-summary".equals(path)) {
                return summaryResponse(service.summarize(
                    LocalDate.parse(requiredQuery(request, "periodStart")),
                    LocalDate.parse(requiredQuery(request, "periodEnd")),
                    optionalQueryDate(request, "asOf", LocalDate.now()),
                    requiredQuery(request, "currency")
                ));
            }
            return response(404, "{\"message\":\"Route not found\"}");
        } catch (IllegalArgumentException | DateTimeParseException exception) {
            return response(400, "{\"message\":\"Invalid income request\"}");
        } catch (JsonProcessingException exception) {
            return response(400, "{\"message\":\"Invalid JSON request body\"}");
        } catch (SdkException exception) {
            return response(503, "{\"message\":\"Income service is unavailable\"}");
        }
    }

    private ManageIncomeSourceUseCase serviceFor(String principal) {
        if (configuredService != null) {
            return configuredService;
        }
        if (configuredFactory != null) {
            return configuredFactory.create(principal);
        }
        DynamoDbClient client = DynamoDbClient.create();
        String tableName = requiredEnvironment("TABLE_NAME");
        return new IncomeSourceService(
            new AwsDynamoDbIncomeSourceRepositoryAdapter(client, tableName, principal),
            new AwsDynamoDbAccountTransactionRepositoryAdapter(client, tableName, principal)
        );
    }

    private APIGatewayV2HTTPResponse sourcesResponse(
        List<IncomeSource> sources, List<IncomeSuggestion> suggestions
    ) throws JsonProcessingException {
        return response(200, JSON.writeValueAsString(Map.of(
            "sources", sources.stream().map(this::sourcePayload).toList(),
            "suggestions", suggestions.stream().map(suggestion -> Map.of(
                "source", sourcePayload(suggestion.source()), "confidence", suggestion.confidence()
            )).toList()
        )));
    }

    private APIGatewayV2HTTPResponse sourceResponse(int status, IncomeSource source)
        throws JsonProcessingException {
        return response(status, JSON.writeValueAsString(sourcePayload(source)));
    }

    private APIGatewayV2HTTPResponse summaryResponse(IncomeSummary summary) throws JsonProcessingException {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("periodStart", summary.periodStart().toString());
        payload.put("periodEnd", summary.periodEnd().toString());
        payload.put("asOf", summary.asOf().toString());
        payload.put("currency", summary.observed().currency());
        payload.put("observed", summary.observed().amount().toPlainString());
        payload.put("expected", summary.expected().amount().toPlainString());
        payload.put("uncertain", summary.uncertain().amount().toPlainString());
        payload.put("confirmedSourceCount", summary.confirmedSourceCount());
        payload.put("unconfirmedSuggestionCount", summary.unconfirmedSuggestionCount());
        return response(200, JSON.writeValueAsString(payload));
    }

    private Map<String, Object> sourcePayload(IncomeSource source) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("id", source.id());
        payload.put("name", source.name());
        payload.put("type", source.type().name());
        payload.put("amount", source.amount().amount().toPlainString());
        payload.put("currency", source.amount().currency());
        payload.put("cadence", source.cadence().name());
        payload.put("effectiveFrom", source.effectiveFrom().toString());
        payload.put("effectiveTo", source.effectiveTo() == null ? null : source.effectiveTo().toString());
        payload.put("linkedAccountId", source.linkedAccountId().value());
        payload.put("confirmationStatus", source.confirmationStatus().name());
        payload.put("sourceTransactionIds", source.sourceTransactionIds().stream().map(TransactionId::value).sorted().toList());
        return payload;
    }

    private JsonNode body(APIGatewayV2HTTPEvent request) throws JsonProcessingException {
        JsonNode parsed = JSON.readTree(request.getBody());
        if (parsed == null || parsed.isNull()) {
            throw new IllegalArgumentException("Request body is required");
        }
        return parsed;
    }

    private Set<TransactionId> transactionIds(JsonNode body) {
        JsonNode ids = body.path("sourceTransactionIds");
        if (!ids.isArray()) {
            throw new IllegalArgumentException("sourceTransactionIds must be an array");
        }
        Set<TransactionId> transactionIds = new LinkedHashSet<>();
        for (JsonNode id : ids) {
            if (!id.isTextual() || id.asText().isBlank()) {
                throw new IllegalArgumentException("sourceTransactionIds must contain non-blank text");
            }
            transactionIds.add(new TransactionId(id.asText()));
        }
        return Set.copyOf(transactionIds);
    }

    private boolean effectiveDatesPath(String path) {
        return path != null && path.matches("/v2/income-sources/[^/]+/effective-dates");
    }

    private boolean confirmationPath(String path, String operation) {
        return path != null && path.matches("/v2/income-sources/[^/]+/suggestion" + operation);
    }

    private String pathId(String path, String suffix) {
        return path.substring("/v2/income-sources/".length(), path.length() - suffix.length());
    }

    private String requiredQuery(APIGatewayV2HTTPEvent request, String name) {
        String value = query(request, name);
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(name + " is required");
        }
        return value;
    }

    private LocalDate optionalQueryDate(APIGatewayV2HTTPEvent request, String name, LocalDate defaultValue) {
        String value = query(request, name);
        return value == null || value.isBlank() ? defaultValue : LocalDate.parse(value);
    }

    private String query(APIGatewayV2HTTPEvent request, String name) {
        return request.getQueryStringParameters() == null ? null : request.getQueryStringParameters().get(name);
    }

    private String requiredText(JsonNode body, String field) {
        String value = body.path(field).asText(null);
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(field + " is required");
        }
        return value;
    }

    private LocalDate optionalDate(JsonNode body, String field) {
        String value = body.path(field).asText(null);
        return value == null || value.isBlank() ? null : LocalDate.parse(value);
    }

    private String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(name + " is not configured");
        }
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
    interface IncomeServiceFactory {
        ManageIncomeSourceUseCase create(String ledgerScope);
    }
}
