package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.automaticexpense.tracker.application.RecurringCommitmentService;
import com.automaticexpense.tracker.application.port.in.ManageRecurringCommitmentsUseCase;
import com.automaticexpense.tracker.domain.ExpectedAmountRange;
import com.automaticexpense.tracker.domain.RecurringCommitment;
import com.automaticexpense.tracker.domain.RecurringCommitmentCadence;
import com.automaticexpense.tracker.domain.RecurringCommitmentClassification;
import com.automaticexpense.tracker.domain.RecurringCommitmentSummary;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbAccountTransactionRepositoryAdapter;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbBillRepositoryAdapter;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbIncomeSourceRepositoryAdapter;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbLoanCardEmiRepositoryAdapter;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbRecurringCommitmentRepositoryAdapter;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Authenticated HTTP adapter for user-controlled recurring commitment decisions. */
public final class RecurringCommitmentHandler
    implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {
    private static final ObjectMapper JSON = new ObjectMapper();
    private final ManageRecurringCommitmentsUseCase configuredService;
    private final ServiceFactory configuredFactory;

    public RecurringCommitmentHandler() {
        configuredService = null;
        configuredFactory = null;
    }

    public RecurringCommitmentHandler(ManageRecurringCommitmentsUseCase configuredService) {
        this.configuredService = configuredService;
        configuredFactory = null;
    }

    RecurringCommitmentHandler(ServiceFactory configuredFactory) {
        configuredService = null;
        this.configuredFactory = configuredFactory;
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent request, Context context) {
        String ledgerScope = AuthenticatedLedgerIdentity.ledgerScope(request);
        if (ledgerScope == null) {
            return response(401, "{\"message\":\"Authentication is required\"}");
        }
        try {
            ManageRecurringCommitmentsUseCase service = serviceFor(ledgerScope);
            String method = request.getRequestContext().getHttp().getMethod();
            String path = request.getRawPath();
            LocalDate asOf = optionalAsOf(request);
            if ("GET".equals(method) && "/v2/recurring-commitments".equals(path)) {
                service.detectCandidates(asOf);
                return response(200, JSON.writeValueAsString(Map.of(
                    "asOf", asOf.toString(),
                    "commitments", service.list(asOf).stream().map(this::payload).toList()
                )));
            }
            if ("POST".equals(method) && "/v2/recurring-commitments".equals(path)) {
                JsonNode body = body(request);
                return commitmentResponse(201, service.create(
                    requiredText(body, "name"),
                    RecurringCommitmentClassification.valueOf(requiredText(body, "classification")),
                    RecurringCommitmentCadence.valueOf(requiredText(body, "cadence")),
                    amountRange(body),
                    LocalDate.parse(requiredText(body, "nextPaymentDate"))
                ));
            }
            if ("GET".equals(method) && "/v2/recurring-commitments/summary".equals(path)) {
                return response(200, JSON.writeValueAsString(summaryPayload(
                    service.summarizeFixedCosts(asOf, requiredQuery(request, "currency"))
                )));
            }
            if ("PUT".equals(method) && idPath(path)) {
                JsonNode body = body(request);
                return commitmentResponse(200, service.correct(
                    id(path), requiredText(body, "name"),
                    RecurringCommitmentClassification.valueOf(requiredText(body, "classification")),
                    RecurringCommitmentCadence.valueOf(requiredText(body, "cadence")),
                    amountRange(body), LocalDate.parse(requiredText(body, "nextPaymentDate"))
                ));
            }
            if ("POST".equals(method) && operationPath(path, "confirm")) {
                return commitmentResponse(200, service.confirm(id(path)));
            }
            if ("POST".equals(method) && operationPath(path, "ignore")) {
                return commitmentResponse(200, service.ignore(id(path)));
            }
            if ("POST".equals(method) && operationPath(path, "cancel")) {
                return commitmentResponse(200, service.cancel(id(path)));
            }
            if ("POST".equals(method) && operationPath(path, "restore")) {
                return commitmentResponse(200, service.restore(id(path)));
            }
            return response(404, "{\"message\":\"Route not found\"}");
        } catch (IllegalArgumentException | IllegalStateException exception) {
            return response(400, "{\"message\":\"Invalid recurring commitment request\"}");
        } catch (JsonProcessingException exception) {
            return response(400, "{\"message\":\"Invalid JSON request body\"}");
        } catch (SdkException exception) {
            return response(503, "{\"message\":\"Recurring commitment service is unavailable\"}");
        }
    }

    private ManageRecurringCommitmentsUseCase serviceFor(String principal) {
        if (configuredService != null) return configuredService;
        if (configuredFactory != null) return configuredFactory.create(principal);
        DynamoDbClient client = DynamoDbClient.create();
        String tableName = requiredEnvironment("TABLE_NAME");
        AwsDynamoDbLoanCardEmiRepositoryAdapter creditCommitments =
            new AwsDynamoDbLoanCardEmiRepositoryAdapter(client, tableName, principal);
        return new RecurringCommitmentService(
            new AwsDynamoDbRecurringCommitmentRepositoryAdapter(client, tableName, principal),
            new AwsDynamoDbAccountTransactionRepositoryAdapter(client, tableName, principal),
            new AwsDynamoDbBillRepositoryAdapter(client, tableName, principal),
            creditCommitments,
            creditCommitments,
            new AwsDynamoDbIncomeSourceRepositoryAdapter(client, tableName, principal)
        );
    }

    private APIGatewayV2HTTPResponse commitmentResponse(int status, RecurringCommitment commitment)
        throws JsonProcessingException {
        return response(status, JSON.writeValueAsString(payload(commitment)));
    }

    private Map<String, Object> payload(RecurringCommitment commitment) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("id", commitment.id());
        result.put("name", commitment.name());
        result.put("classification", commitment.classification().name());
        result.put("cadence", commitment.cadence().name());
        result.put("minimumAmount", commitment.expectedAmountRange().minimum().amount().toPlainString());
        result.put("maximumAmount", commitment.expectedAmountRange().maximum().amount().toPlainString());
        result.put("currency", commitment.expectedAmountRange().minimum().currency());
        result.put("nextPaymentDate", commitment.nextPaymentDate().toString());
        result.put("confidence", commitment.confidence());
        result.put("supportingTransactionIds", commitment.supportingTransactionIds().stream()
            .map(transactionId -> transactionId.value()).sorted().toList());
        result.put("status", commitment.status().name());
        result.put("state", commitment.state().name());
        result.put("origin", commitment.origin().name());
        result.put("authoritativeReference", commitment.authoritativeReference());
        return result;
    }

    private Map<String, Object> summaryPayload(RecurringCommitmentSummary summary) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("asOf", summary.asOf().toString());
        result.put("formulaId", summary.formulaId());
        result.put("classification", summary.classification().name());
        result.put("currency", summary.confirmedFixedMonthlyCost().currency());
        result.put("confirmedFixedMonthlyCost", summary.confirmedFixedMonthlyCost().amount().toPlainString());
        result.put("variableMonthlyCost", summary.variableMonthlyCost().amount().toPlainString());
        result.put("confirmedFixedMonthlyIncome", summary.confirmedFixedMonthlyIncome().amount().toPlainString());
        result.put("fixedCostRatio", summary.fixedCostRatio() == null ? null : summary.fixedCostRatio().toPlainString());
        result.put("confirmedCommitmentCount", summary.confirmedCommitmentCount());
        result.put("variableCommitmentCount", summary.variableCommitmentCount());
        result.put("warnings", summary.warnings());
        return result;
    }

    private ExpectedAmountRange amountRange(JsonNode body) {
        String currency = requiredText(body, "currency");
        return new ExpectedAmountRange(
            Money.of(requiredText(body, "minimumAmount"), currency),
            Money.of(requiredText(body, "maximumAmount"), currency)
        );
    }

    private JsonNode body(APIGatewayV2HTTPEvent request) throws JsonProcessingException {
        JsonNode parsed = JSON.readTree(request.getBody());
        if (parsed == null || parsed.isNull()) throw new IllegalArgumentException("Request body is required");
        return parsed;
    }

    private LocalDate optionalAsOf(APIGatewayV2HTTPEvent request) {
        String asOf = query(request, "asOf");
        return asOf == null || asOf.isBlank() ? LocalDate.now() : LocalDate.parse(asOf);
    }

    private String requiredQuery(APIGatewayV2HTTPEvent request, String name) {
        String value = query(request, name);
        if (value == null || value.isBlank()) throw new IllegalArgumentException(name + " is required");
        return value;
    }

    private String query(APIGatewayV2HTTPEvent request, String name) {
        return request.getQueryStringParameters() == null ? null : request.getQueryStringParameters().get(name);
    }

    private String requiredText(JsonNode body, String field) {
        String value = body.path(field).asText(null);
        if (value == null || value.isBlank()) throw new IllegalArgumentException(field + " is required");
        return value;
    }

    private boolean idPath(String path) {
        return path != null && path.matches("/v2/recurring-commitments/[^/]+");
    }

    private boolean operationPath(String path, String operation) {
        return path != null && path.matches("/v2/recurring-commitments/[^/]+/" + operation);
    }

    private String id(String path) {
        String suffix = path.substring("/v2/recurring-commitments/".length());
        int operation = suffix.indexOf('/');
        return operation < 0 ? suffix : suffix.substring(0, operation);
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
    interface ServiceFactory {
        ManageRecurringCommitmentsUseCase create(String ledgerScope);
    }
}
