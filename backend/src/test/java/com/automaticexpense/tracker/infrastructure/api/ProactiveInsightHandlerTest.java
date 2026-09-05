package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.automaticexpense.tracker.application.port.in.ManageProactiveInsightsUseCase;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class ProactiveInsightHandlerTest {

    @Test
    void servesCurrentPersistedInsightCardsWithTheirBaselineAndEvidence() {
        ProactiveInsightHandler handler = new ProactiveInsightHandler(new StubInsights());

        var response = handler.handleRequest(request("GET", "/v2/insights"), null);

        assertThat(response.getStatusCode()).isEqualTo(200);
        assertThat(response.getBody()).contains(
            "\"classification\":\"DERIVED_INSIGHT\"",
            "\"baselineLabel\":\"three comparable prior months\"",
            "\"freshnessAsOf\":\"2026-08-31T18:30:00Z\"",
            "\"transactionId\":\"txn-1\""
        );
    }

    @Test
    void dismissesAnAuthenticatedUsersInsight() {
        StubInsights insights = new StubInsights();
        ProactiveInsightHandler handler = new ProactiveInsightHandler(insights);

        var response = handler.handleRequest(request("POST", "/v2/insights/insight-1/dismiss"), null);

        assertThat(response.getStatusCode()).isEqualTo(204);
        assertThat(insights.dismissedId).isEqualTo("insight-1");
    }

    private APIGatewayV2HTTPEvent request(String method, String path) {
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
        request.setRequestContext(context);
        return request;
    }

    private static final class StubInsights implements ManageProactiveInsightsUseCase {
        private String dismissedId;

        @Override
        public List<ProactiveInsight> list(String userId, Instant asOf, boolean includeDismissed) {
            return List.of(insight());
        }

        @Override
        public void dismiss(String userId, String insightId) {
            dismissedId = insightId;
        }

        private ProactiveInsight insight() {
            Money amount = Money.of("5000.00", "INR");
            return new ProactiveInsight(
                "insight-1", ProactiveInsightType.CATEGORY_INCREASE, IntelligenceClassification.DERIVED_INSIGHT,
                "Category spending increased", "GROCERIES is higher than usual.", amount, Money.of("2000.00", "INR"),
                "three comparable prior months", new BigDecimal("0.90"),
                Instant.parse("2026-08-31T18:30:00Z"), Instant.parse("2026-08-31T18:30:00Z"),
                ProactiveInsightCalculator.FORMULA,
                new EvidenceMetadata(1, new DrillDownReference(
                    new DateRange(LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31)),
                    "INR", java.util.Set.of(), "GROCERIES", null
                )),
                List.of(new TransactionEvidence("txn-1", LocalDateTime.parse("2026-08-12T10:00"), "Grocer", amount)),
                List.of(), List.of(), "CATEGORY_INCREASE:GROCERIES:2026-08",
                Instant.parse("2026-08-31T18:30:00Z"), Instant.parse("2026-10-01T18:30:00Z"),
                InsightLifecycleState.ACTIVE
            );
        }
    }
}
