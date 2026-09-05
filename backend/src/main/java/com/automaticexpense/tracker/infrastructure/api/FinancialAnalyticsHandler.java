package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.automaticexpense.tracker.application.FinancialCapabilityService;
import com.automaticexpense.tracker.application.FinancialEvidenceService;
import com.automaticexpense.tracker.application.FinancialSnapshotService;
import com.automaticexpense.tracker.application.port.in.EvaluateFinancialCapabilityUseCase;
import com.automaticexpense.tracker.application.port.in.LoadFinancialEvidenceUseCase;
import com.automaticexpense.tracker.application.port.in.LoadFinancialSnapshotUseCase;
import com.automaticexpense.tracker.domain.*;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbFinancialSnapshotRepositoryAdapter;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Authenticated HTTP adapter for deterministic, explainable spending analytics.
 */
public final class FinancialAnalyticsHandler
    implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {

    private static final ObjectMapper JSON = new ObjectMapper();

    private final LoadFinancialSnapshotUseCase snapshots;
    private final EvaluateFinancialCapabilityUseCase capabilities;
    private final LoadFinancialEvidenceUseCase evidence;

    public FinancialAnalyticsHandler() {
        this.snapshots = null;
        this.capabilities = null;
        this.evidence = null;
    }

    public FinancialAnalyticsHandler(
        LoadFinancialSnapshotUseCase snapshots,
        EvaluateFinancialCapabilityUseCase capabilities,
        LoadFinancialEvidenceUseCase evidence
    ) {
        this.snapshots = snapshots;
        this.capabilities = capabilities;
        this.evidence = evidence;
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent request, Context context) {
        if (!"GET".equals(request.getRequestContext().getHttp().getMethod())) {
            return response(404, Map.of("message", "Route not found"));
        }
        String principal = authenticatedEmail(request);
        if (principal == null) {
            return response(401, Map.of("message", "Authentication is required"));
        }
        try {
            Map<String, String> query = request.getQueryStringParameters() == null
                ? Map.of() : request.getQueryStringParameters();
            RequestSelection selection = selection(query);
            String path = request.getRawPath();
            if ("/v2/analytics".equals(path)) {
                IntelligenceResult<FinancialSnapshot> snapshot = snapshots(principal).load(
                    new FinancialSnapshotRequest(
                        selection.asOf(), selection.timezone(), selection.accountIds(), selection.currency()
                    )
                );
                IntelligenceResult<SpendingAnalytics> result = capabilities().evaluate(
                    snapshot.value(), selection.analyticsRequest()
                );
                return response(200, analyticsEnvelope(result));
            }
            if ("/v2/analytics/evidence".equals(path)) {
                IntelligenceResult<FinancialEvidencePage> result = evidence(principal).load(
                    new FinancialEvidenceQuery(
                        selection.analyticsRequest(), selection.asOf(), selection.timezone(),
                        pageSize(query), query.get("cursor")
                    )
                );
                return response(200, evidenceEnvelope(result));
            }
            return response(404, Map.of("message", "Route not found"));
        } catch (IllegalArgumentException exception) {
            return response(400, Map.of("message", exception.getMessage()));
        } catch (SdkException exception) {
            return response(503, Map.of("message", "Financial analytics are unavailable"));
        }
    }

    private LoadFinancialSnapshotUseCase snapshots(String principal) {
        if (snapshots != null) {
            return snapshots;
        }
        AwsDynamoDbFinancialSnapshotRepositoryAdapter repository = repository(principal);
        return new FinancialSnapshotService(repository);
    }

    private EvaluateFinancialCapabilityUseCase capabilities() {
        return capabilities != null
            ? capabilities
            : new FinancialCapabilityService(new SpendingAnalyticsCalculator());
    }

    private LoadFinancialEvidenceUseCase evidence(String principal) {
        if (evidence != null) {
            return evidence;
        }
        return new FinancialEvidenceService(repository(principal));
    }

    private AwsDynamoDbFinancialSnapshotRepositoryAdapter repository(String principal) {
        return new AwsDynamoDbFinancialSnapshotRepositoryAdapter(
            DynamoDbClient.create(), requiredEnvironment("TABLE_NAME"), userScopeId(principal)
        );
    }

    private RequestSelection selection(Map<String, String> query) {
        String month = query.getOrDefault("month", YearMonth.now().toString());
        YearMonth parsedMonth;
        try {
            parsedMonth = YearMonth.parse(month);
        } catch (RuntimeException exception) {
            throw new IllegalArgumentException("month must use YYYY-MM format");
        }
        String currency = query.getOrDefault("currency", "INR");
        if (!currency.matches("[A-Z]{3}")) {
            throw new IllegalArgumentException("currency must be a three-letter uppercase ISO code");
        }
        ZoneId timezone;
        try {
            timezone = ZoneId.of(query.getOrDefault("timezone", "Asia/Kolkata"));
        } catch (RuntimeException exception) {
            throw new IllegalArgumentException("timezone must be an IANA timezone");
        }
        Instant asOf;
        try {
            asOf = query.containsKey("asOf") ? Instant.parse(query.get("asOf")) : Instant.now();
        } catch (RuntimeException exception) {
            throw new IllegalArgumentException("asOf must be an ISO-8601 instant");
        }
        Set<AccountId> accountIds = List.of(query.getOrDefault("accountIds", "").split(",")).stream()
            .filter(value -> !value.isBlank())
            .map(AccountId::new)
            .collect(Collectors.toUnmodifiableSet());
        DateRange period = new DateRange(parsedMonth.atDay(1), parsedMonth.atEndOfMonth());
        return new RequestSelection(
            asOf,
            timezone,
            currency,
            accountIds,
            blankToNull(query.get("categoryId")),
            blankToNull(query.get("merchantName")),
            new SpendingAnalyticsRequest(period, currency, accountIds, blankToNull(query.get("categoryId")),
                blankToNull(query.get("merchantName")), rollingPeriodCount(query))
        );
    }

    private int rollingPeriodCount(Map<String, String> query) {
        int count = parsePositiveInt(query.getOrDefault("rollingPeriods", "3"), "rollingPeriods");
        if (count > 24) {
            throw new IllegalArgumentException("rollingPeriods must be at most 24");
        }
        return count;
    }

    private int pageSize(Map<String, String> query) {
        int size = parsePositiveInt(query.getOrDefault("limit", "25"), "limit");
        if (size > 100) {
            throw new IllegalArgumentException("limit must be at most 100");
        }
        return size;
    }

    private int parsePositiveInt(String text, String name) {
        try {
            int value = Integer.parseInt(text);
            if (value < 1) {
                throw new NumberFormatException();
            }
            return value;
        } catch (NumberFormatException exception) {
            throw new IllegalArgumentException(name + " must be a positive integer");
        }
    }

    private Map<String, Object> analyticsEnvelope(IntelligenceResult<SpendingAnalytics> result) {
        Map<String, Object> payload = envelope(result);
        SpendingAnalytics value = result.value();
        payload.put("value", Map.ofEntries(
            Map.entry("currentPeriod", period(value.currentPeriod())),
            Map.entry("previousPeriod", period(value.previousPeriod())),
            Map.entry("yearOverYearPeriod", period(value.yearOverYearPeriod())),
            Map.entry("monthOverMonth", comparison(value.monthOverMonth())),
            Map.entry("yearOverYear", comparison(value.yearOverYear())),
            Map.entry("rollingAverage", money(value.rollingAverage())),
            Map.entry("transactionFrequency", value.transactionFrequency()),
            Map.entry("averageTransactionValue", money(value.averageTransactionValue())),
            Map.entry("categoryBreakdown", breakdown(value.categoryBreakdown())),
            Map.entry("merchantBreakdown", breakdown(value.merchantBreakdown())),
            Map.entry("accountBreakdown", breakdown(value.accountBreakdown())),
            Map.entry("largestPurchases", value.largestPurchases().stream().map(item -> Map.of(
                "transactionId", item.transactionId(),
                "timestamp", item.timestamp().toString(),
                "merchantName", item.merchantName(),
                "personalSpend", money(item.personalSpend())
            )).toList()),
            Map.entry("highestPeriod", period(value.highestPeriod())),
            Map.entry("lowestPeriod", period(value.lowestPeriod()))
        ));
        return payload;
    }

    private Map<String, Object> evidenceEnvelope(IntelligenceResult<FinancialEvidencePage> result) {
        Map<String, Object> payload = envelope(result);
        Map<String, Object> value = new LinkedHashMap<>();
        value.put("items", result.value().transactions().stream().map(this::transaction).toList());
        value.put("nextCursor", result.value().nextCursor());
        payload.put("value", value);
        return payload;
    }

    private <T> Map<String, Object> envelope(IntelligenceResult<T> result) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("classification", result.classification().name());
        payload.put("asOf", result.asOf().toString());
        payload.put("freshnessAsOf", result.freshnessAsOf().toString());
        payload.put("confidence", result.confidence());
        payload.put("formula", Map.of("id", result.formula().id(), "version", result.formula().version()));
        Map<String, Object> evidence = new LinkedHashMap<>();
        evidence.put("sourceCount", result.evidence().sourceCount());
        if (result.evidence().drillDown() != null) {
            DrillDownReference drillDown = result.evidence().drillDown();
            evidence.put("drillDown", Map.of(
                "start", drillDown.period().start().toString(),
                "end", drillDown.period().end().toString(),
                "currency", drillDown.currency(),
                "accountIds", drillDown.accountIds().stream().map(AccountId::value).sorted().toList(),
                "categoryId", drillDown.categoryId() == null ? "" : drillDown.categoryId(),
                "merchantName", drillDown.merchantName() == null ? "" : drillDown.merchantName()
            ));
        }
        payload.put("evidence", evidence);
        payload.put("assumptions", result.assumptions());
        payload.put("warnings", result.warnings().stream().map(Enum::name).toList());
        return payload;
    }

    private Map<String, Object> period(PeriodSpending period) {
        return Map.of(
            "start", period.period().start().toString(),
            "end", period.period().end().toString(),
            "total", money(period.total()),
            "transactionCount", period.transactionCount()
        );
    }

    private Map<String, Object> comparison(PeriodComparison comparison) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("baseline", period(comparison.baseline()));
        result.put("absoluteChange", money(comparison.absoluteChange()));
        result.put("percentageChange", comparison.percentageChange());
        return result;
    }

    private List<Map<String, Object>> breakdown(List<SpendingBreakdown> breakdown) {
        return breakdown.stream().map(item -> Map.of(
            "key", item.key(),
            "total", money(item.total()),
            "transactionCount", item.transactionCount()
        )).toList();
    }

    private Map<String, Object> transaction(Transaction transaction) {
        return Map.of(
            "id", transaction.id().value(),
            "amount", transaction.amount().amount(),
            "currency", transaction.amount().currency(),
            "type", transaction.type().name(),
            "merchantName", transaction.merchantName(),
            "accountId", transaction.accountId().value(),
            "categoryId", transaction.categoryId() == null ? "UNCATEGORIZED" : transaction.categoryId(),
            "timestamp", transaction.timestamp().toString(),
            "netPersonalExpense", transaction.netPersonalExpense().amount()
        );
    }

    private Map<String, Object> money(Money money) {
        return Map.of("amount", money.amount(), "currency", money.currency());
    }

    private APIGatewayV2HTTPResponse response(int status, Map<String, ?> payload) {
        try {
            return APIGatewayV2HTTPResponse.builder()
                .withStatusCode(status)
                .withHeaders(Map.of("Content-Type", "application/json"))
                .withBody(JSON.writeValueAsString(payload))
                .build();
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to serialize analytics response", exception);
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

    private String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
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

    private record RequestSelection(
        Instant asOf,
        ZoneId timezone,
        String currency,
        Set<AccountId> accountIds,
        String categoryId,
        String merchantName,
        SpendingAnalyticsRequest analyticsRequest
    ) {}
}
