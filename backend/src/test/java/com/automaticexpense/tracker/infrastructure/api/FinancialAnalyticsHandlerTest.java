package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.automaticexpense.tracker.application.port.in.EvaluateFinancialCapabilityUseCase;
import com.automaticexpense.tracker.application.port.in.LoadFinancialEvidenceUseCase;
import com.automaticexpense.tracker.application.port.in.LoadFinancialSnapshotUseCase;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class FinancialAnalyticsHandlerTest {

    @Test
    void servesAnAuthenticatedDeterministicAnalyticsEnvelope() {
        FinancialSnapshot snapshot = new FinancialSnapshot(
            Instant.parse("2026-08-31T12:00:00Z"), ZoneId.of("Asia/Kolkata"), List.of()
        );
        FinancialAnalyticsHandler handler = new FinancialAnalyticsHandler(
            request -> result(snapshot, "financial-snapshot"),
            (loaded, request) -> result(analytics(), "spending-analytics"),
            request -> result(new FinancialEvidencePage(List.of(), null), "financial-evidence")
        );

        var response = handler.handleRequest(request(
            "GET", "/v2/analytics", Map.of("month", "2026-08", "timezone", "Asia/Kolkata")
        ), null);

        assertThat(response.getStatusCode()).isEqualTo(200);
        assertThat(response.getBody()).contains(
            "\"classification\":\"FACT\"",
            "\"id\":\"spending-analytics\"",
            "\"version\":\"1.0.0\"",
            "\"asOf\":\"2026-08-31T12:00:00Z\"",
            "\"currentPeriod\""
        );
    }

    @Test
    void rejectsEvidenceRequestsWithoutVerifiedGatewayClaims() {
        FinancialAnalyticsHandler handler = new FinancialAnalyticsHandler(
            request -> { throw new AssertionError("snapshot must not load"); },
            (snapshot, request) -> { throw new AssertionError("analytics must not evaluate"); },
            request -> { throw new AssertionError("evidence must not load"); }
        );

        APIGatewayV2HTTPEvent request = request("GET", "/v2/analytics/evidence", Map.of());
        request.getRequestContext().setAuthorizer(null);
        var response = handler.handleRequest(request, null);

        assertThat(response.getStatusCode()).isEqualTo(401);
    }

    private <T> IntelligenceResult<T> result(T value, String formulaId) {
        return new IntelligenceResult<>(
            IntelligenceClassification.FACT,
            value,
            Instant.parse("2026-08-31T12:00:00Z"),
            Instant.parse("2026-08-31T12:00:00Z"),
            BigDecimal.ONE,
            new FormulaReference(formulaId, "1.0.0"),
            new EvidenceMetadata(0, null),
            List.of(),
            List.of()
        );
    }

    private SpendingAnalytics analytics() {
        DateRange period = new DateRange(LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31));
        PeriodSpending spending = new PeriodSpending(period, Money.of("0.00", "INR"), 0);
        return new SpendingAnalytics(
            spending, spending, spending,
            new PeriodComparison(spending, Money.zero("INR"), null),
            new PeriodComparison(spending, Money.zero("INR"), null),
            Money.zero("INR"), 0, Money.zero("INR"),
            List.of(), List.of(), List.of(), List.of(), spending, spending
        );
    }

    private APIGatewayV2HTTPEvent request(
        String method,
        String path,
        Map<String, String> query
    ) {
        APIGatewayV2HTTPEvent.RequestContext.Http http = new APIGatewayV2HTTPEvent.RequestContext.Http();
        http.setMethod(method);
        APIGatewayV2HTTPEvent.RequestContext context = new APIGatewayV2HTTPEvent.RequestContext();
        context.setHttp(http);
        APIGatewayV2HTTPEvent.RequestContext.Authorizer authorizer =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer();
        APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT jwt =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT();
        jwt.setClaims(Map.of("email", "person@example.com", "email_verified", "true"));
        authorizer.setJwt(jwt);
        context.setAuthorizer(authorizer);
        APIGatewayV2HTTPEvent request = new APIGatewayV2HTTPEvent();
        request.setRawPath(path);
        request.setQueryStringParameters(query);
        request.setRequestContext(context);
        return request;
    }
}
