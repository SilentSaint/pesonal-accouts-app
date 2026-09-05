package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.automaticexpense.tracker.application.FinancialContextService;
import com.automaticexpense.tracker.application.port.out.FinancialContextRepository;
import com.automaticexpense.tracker.domain.FinancialContextItem;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

class FinancialContextHandlerTest {

    @Test
    void createsListsAndDeactivatesUserDeclaredContextAtTheAuthenticatedHttpSeam() {
        FinancialContextHandler handler = new FinancialContextHandler(
            new FinancialContextService(new InMemoryRepository(), () -> Instant.parse("2026-08-29T10:00:00Z"))
        );
        String body = """
            {"type":"PREFERRED_MINIMUM_CASH_BALANCE","label":"Cash floor",
             "values":{"amount":"25000.00","currency":"INR"},
             "capabilities":["CASH_FLOW_FORECAST"],"provenance":"USER_DECLARED",
             "effectiveFrom":"2026-08-01"}""";

        var created = handler.handleRequest(authenticated("POST", "/v2/financial-context", body), null);
        var listed = handler.handleRequest(authenticated("GET", "/v2/financial-context", null), null);
        String id = created.getBody().replaceFirst(".*\"id\":\"([^\"]+)\".*", "$1");
        var deactivated = handler.handleRequest(authenticated(
            "POST", "/v2/financial-context/" + id + "/deactivate", null
        ), null);

        assertThat(created.getStatusCode()).isEqualTo(201);
        assertThat(listed.getBody()).contains("\"status\":\"ACTIVE\"", "\"provenance\":\"USER_DECLARED\"");
        assertThat(deactivated.getBody()).contains("\"active\":false");
    }

    @Test
    void rejectsARequestWithoutTheVerifiedGatewaySubjectClaim() {
        FinancialContextHandler handler = new FinancialContextHandler(
            new FinancialContextService(new InMemoryRepository())
        );

        var response = handler.handleRequest(request("GET", "/v2/financial-context"), null);

        assertThat(response.getStatusCode()).isEqualTo(401);
    }

    private APIGatewayV2HTTPEvent authenticated(String method, String path, String body) {
        APIGatewayV2HTTPEvent request = request(method, path);
        APIGatewayV2HTTPEvent.RequestContext.Authorizer authorizer =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer();
        APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT jwt =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT();
        jwt.setClaims(Map.of(
            "sub", "opaque-subject",
            "email", "context@example.com",
            "email_verified", "true"
        ));
        authorizer.setJwt(jwt);
        request.getRequestContext().setAuthorizer(authorizer);
        request.setBody(body);
        return request;
    }

    private APIGatewayV2HTTPEvent request(String method, String path) {
        APIGatewayV2HTTPEvent.RequestContext.Http http =
            new APIGatewayV2HTTPEvent.RequestContext.Http();
        http.setMethod(method);
        APIGatewayV2HTTPEvent.RequestContext requestContext =
            new APIGatewayV2HTTPEvent.RequestContext();
        requestContext.setHttp(http);
        APIGatewayV2HTTPEvent request = new APIGatewayV2HTTPEvent();
        request.setRawPath(path);
        request.setRequestContext(requestContext);
        return request;
    }

    private static final class InMemoryRepository implements FinancialContextRepository {
        private final List<FinancialContextItem> items = new ArrayList<>();

        @Override
        public void save(FinancialContextItem item) {
            delete(item.id());
            items.add(item);
        }

        @Override
        public Optional<FinancialContextItem> findById(String id) {
            return items.stream().filter(item -> item.id().equals(id)).findFirst();
        }

        @Override
        public List<FinancialContextItem> findAll() {
            return List.copyOf(items);
        }

        @Override
        public void delete(String id) {
            items.removeIf(item -> item.id().equals(id));
        }
    }
}
