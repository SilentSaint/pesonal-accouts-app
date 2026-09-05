package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.automaticexpense.tracker.application.FinancialGoalService;
import com.automaticexpense.tracker.application.port.out.FinancialGoalRepository;
import com.automaticexpense.tracker.domain.FinancialGoal;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

class FinancialGoalHandlerTest {

    @Test
    void createsAndListsProjectionsAtTheAuthenticatedHttpSeam() {
        FinancialGoalHandler handler = new FinancialGoalHandler(new FinancialGoalService(new InMemoryGoals()));
        String body = """
            {"name":"Car","targetAmount":"1200.00","currency":"INR","targetDate":"2026-06-30",
             "priority":"HIGH","allocations":[{"reference":"car-savings","amount":"200.00",
             "linkedAccountId":"savings"}]}""";

        var created = handler.handleRequest(authenticated("POST", "/v2/financial-goals", body), null);
        var listed = handler.handleRequest(authenticated("GET", "/v2/financial-goals", null), null);

        assertThat(created.getStatusCode()).isEqualTo(201);
        assertThat(listed.getStatusCode()).isEqualTo(200);
        assertThat(listed.getBody()).contains("\"classification\":\"PREDICTION\"", "\"formula\"");
    }

    @Test
    void rejectsRequestsWithoutTheVerifiedGatewaySubjectClaim() {
        FinancialGoalHandler handler = new FinancialGoalHandler(new FinancialGoalService(new InMemoryGoals()));

        assertThat(handler.handleRequest(request("GET", "/v2/financial-goals"), null).getStatusCode()).isEqualTo(401);
    }

    private APIGatewayV2HTTPEvent authenticated(String method, String path, String body) {
        APIGatewayV2HTTPEvent event = request(method, path);
        APIGatewayV2HTTPEvent.RequestContext.Authorizer authorizer =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer();
        APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT jwt =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT();
        jwt.setClaims(java.util.Map.of("sub", "subject", "email", "goals@example.com", "email_verified", "true"));
        authorizer.setJwt(jwt);
        event.getRequestContext().setAuthorizer(authorizer);
        event.setBody(body);
        return event;
    }

    private APIGatewayV2HTTPEvent request(String method, String path) {
        APIGatewayV2HTTPEvent.RequestContext.Http http = new APIGatewayV2HTTPEvent.RequestContext.Http();
        http.setMethod(method);
        APIGatewayV2HTTPEvent.RequestContext context = new APIGatewayV2HTTPEvent.RequestContext();
        context.setHttp(http);
        APIGatewayV2HTTPEvent event = new APIGatewayV2HTTPEvent();
        event.setRawPath(path);
        event.setRequestContext(context);
        return event;
    }

    private static final class InMemoryGoals implements FinancialGoalRepository {
        private final List<FinancialGoal> goals = new ArrayList<>();

        @Override public void save(FinancialGoal goal) {
            goals.removeIf(existing -> existing.id().equals(goal.id()));
            goals.add(goal);
        }
        @Override public Optional<FinancialGoal> findById(String id) {
            return goals.stream().filter(goal -> goal.id().equals(id)).findFirst();
        }
        @Override public List<FinancialGoal> findAll() { return List.copyOf(goals); }
        @Override public void deleteById(String id) { goals.removeIf(goal -> goal.id().equals(id)); }
    }
}
