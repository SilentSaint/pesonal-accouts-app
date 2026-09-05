package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.automaticexpense.tracker.application.FinanceQueryAliasRegistry;
import com.automaticexpense.tracker.domain.FinanceQueryClarification;
import com.automaticexpense.tracker.domain.FinancialSnapshot;
import com.automaticexpense.tracker.domain.IntelligenceResult;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class FinanceQueryHandlerTest {

    @Test
    void returnsAClarificationForAnAmbiguousAuthenticatedQuestion() {
        FinancialSnapshot snapshot = new FinancialSnapshot(
            Instant.parse("2026-08-31T18:30:00Z"), ZoneId.of("Asia/Kolkata"), List.of()
        );
        FinanceQueryHandler handler = new FinanceQueryHandler(
            ignored -> new IntelligenceResult<>(
                com.automaticexpense.tracker.domain.IntelligenceClassification.FACT,
                snapshot,
                snapshot.asOf(),
                snapshot.asOf(),
                BigDecimal.ONE,
                new com.automaticexpense.tracker.domain.FormulaReference("financial-snapshot", "1.0.0"),
                new com.automaticexpense.tracker.domain.EvidenceMetadata(0, null),
                List.of(),
                List.of()
            ),
            (query, aliases) -> new FinanceQueryClarification("Please select a period."),
            (loaded, request) -> {
                throw new AssertionError("ambiguous queries must not evaluate a capability");
            },
            (plan, result) -> {
                throw new AssertionError("ambiguous queries must not compose an answer");
            },
            new FinanceQueryAliasRegistry()
        );

        var response = handler.handleRequest(request(true), null);

        assertThat(response.getStatusCode()).isEqualTo(200);
        assertThat(response.getBody()).contains(
            "\"status\":\"CLARIFICATION\"",
            "\"message\":\"Please select a period.\""
        );
    }

    @Test
    void rejectsFinanceQueriesWithoutVerifiedGatewayClaims() {
        FinanceQueryHandler handler = new FinanceQueryHandler(
            ignored -> { throw new AssertionError("snapshot must not load"); },
            (query, aliases) -> { throw new AssertionError("planner must not run"); },
            (loaded, request) -> { throw new AssertionError("capability must not run"); },
            (plan, result) -> { throw new AssertionError("composer must not run"); },
            new FinanceQueryAliasRegistry()
        );

        var response = handler.handleRequest(request(false), null);

        assertThat(response.getStatusCode()).isEqualTo(401);
    }

    private APIGatewayV2HTTPEvent request(boolean authenticated) {
        APIGatewayV2HTTPEvent.RequestContext.Http http = new APIGatewayV2HTTPEvent.RequestContext.Http();
        http.setMethod("POST");
        APIGatewayV2HTTPEvent.RequestContext context = new APIGatewayV2HTTPEvent.RequestContext();
        context.setHttp(http);
        if (authenticated) {
            APIGatewayV2HTTPEvent.RequestContext.Authorizer authorizer =
                new APIGatewayV2HTTPEvent.RequestContext.Authorizer();
            APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT jwt =
                new APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT();
            jwt.setClaims(Map.of("email", "person@example.com", "email_verified", "true"));
            authorizer.setJwt(jwt);
            context.setAuthorizer(authorizer);
        }
        APIGatewayV2HTTPEvent request = new APIGatewayV2HTTPEvent();
        request.setRawPath("/v2/finance-queries");
        request.setBody("{\"question\":\"what did I spend?\",\"asOf\":\"2026-08-31T18:30:00Z\"}");
        request.setRequestContext(context);
        return request;
    }
}
