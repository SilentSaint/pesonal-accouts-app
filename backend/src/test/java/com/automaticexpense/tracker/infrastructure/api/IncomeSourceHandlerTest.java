package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.automaticexpense.tracker.application.IncomeSourceService;
import com.automaticexpense.tracker.application.port.out.IncomeSourceRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IncomeSource;
import com.automaticexpense.tracker.domain.IncomeConfirmationStatus;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

class IncomeSourceHandlerTest {

    @Test
    void createsAndListsIncomeSourcesAtTheAuthenticatedHttpSeam() {
        IncomeSourceHandler handler = new IncomeSourceHandler(
            new IncomeSourceService(new InMemoryIncomeSources(), new EmptyTransactions())
        );
        String body = """
            {"name":"Acme Payroll","type":"FIXED","amount":"75000.00","currency":"INR",
             "cadence":"MONTHLY","effectiveFrom":"2026-01-31","linkedAccountId":"account-1",
             "sourceTransactionIds":[]}""";

        var created = handler.handleRequest(authenticated("POST", "/v2/income-sources", body), null);
        var listed = handler.handleRequest(authenticated("GET", "/v2/income-sources", null), null);

        assertThat(created.getStatusCode()).isEqualTo(201);
        assertThat(created.getBody()).contains("\"confirmationStatus\":\"CONFIRMED\"");
        assertThat(listed.getStatusCode()).isEqualTo(200);
        assertThat(listed.getBody()).contains(
            "\"name\":\"Acme Payroll\"", "\"sources\"", "\"suggestions\""
        );
    }

    @Test
    void rejectsARequestWithoutTheVerifiedGatewaySubjectClaim() {
        IncomeSourceHandler handler = new IncomeSourceHandler(
            new IncomeSourceService(new InMemoryIncomeSources(), new EmptyTransactions())
        );

        assertThat(handler.handleRequest(request("GET", "/v2/income-sources"), null).getStatusCode())
            .isEqualTo(401);
    }

    @Test
    void usesTheVerifiedEmailLedgerScopeForBothIncomeAndCanonicalTransactionAccess() {
        AtomicReference<String> usedScope = new AtomicReference<>();
        IncomeSourceHandler handler = new IncomeSourceHandler(scope -> {
            usedScope.set(scope);
            return new IncomeSourceService(new InMemoryIncomeSources(), new EmptyTransactions());
        });

        var response = handler.handleRequest(authenticated("GET", "/v2/income-sources", null), null);

        assertThat(response.getStatusCode()).isEqualTo(200);
        assertThat(usedScope.get()).isEqualTo("24c7a3b9549715d94650d0ecac0d1de6");
    }

    private APIGatewayV2HTTPEvent authenticated(String method, String path, String body) {
        APIGatewayV2HTTPEvent request = request(method, path);
        APIGatewayV2HTTPEvent.RequestContext.Authorizer authorizer =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer();
        APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT jwt =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT();
        jwt.setClaims(java.util.Map.of(
            "sub", "opaque-subject",
            "email", "income@example.com",
            "email_verified", "true"
        ));
        authorizer.setJwt(jwt);
        request.getRequestContext().setAuthorizer(authorizer);
        request.setBody(body);
        return request;
    }

    private APIGatewayV2HTTPEvent request(String method, String path) {
        APIGatewayV2HTTPEvent.RequestContext.Http http = new APIGatewayV2HTTPEvent.RequestContext.Http();
        http.setMethod(method);
        APIGatewayV2HTTPEvent.RequestContext context = new APIGatewayV2HTTPEvent.RequestContext();
        context.setHttp(http);
        APIGatewayV2HTTPEvent request = new APIGatewayV2HTTPEvent();
        request.setRawPath(path);
        request.setRequestContext(context);
        return request;
    }

    private static final class InMemoryIncomeSources implements IncomeSourceRepository {
        private final List<IncomeSource> sources = new ArrayList<>();

        @Override
        public void save(IncomeSource source) {
            sources.removeIf(existing -> existing.id().equals(source.id()));
            sources.add(source);
        }

        @Override
        public boolean replaceIfPending(IncomeSource source) {
            return findById(source.id())
                .filter(existing -> existing.confirmationStatus() == IncomeConfirmationStatus.PENDING)
                .map(existing -> {
                    save(source);
                    return true;
                })
                .orElse(false);
        }

        @Override
        public Optional<IncomeSource> findById(String id) {
            return sources.stream().filter(source -> source.id().equals(id)).findFirst();
        }

        @Override
        public Optional<IncomeSource> findBySuggestionKey(String key) {
            return sources.stream().filter(source -> key.equals(source.suggestionKey())).findFirst();
        }

        @Override
        public List<IncomeSource> findAll() {
            return List.copyOf(sources);
        }
    }

    private static final class EmptyTransactions implements TransactionRepository {
        @Override public void save(Transaction transaction) {}
        @Override public Optional<Transaction> findById(TransactionId id) { return Optional.empty(); }
        @Override public List<Transaction> findByAccountId(AccountId accountId) { return List.of(); }
        @Override public List<Transaction> findByReconciliationStatus(ReconciliationStatus status) { return List.of(); }
        @Override public List<Transaction> findByAccountIdAndWindow(
            AccountId accountId, LocalDateTime start, LocalDateTime end
        ) { return List.of(); }
        @Override public List<Transaction> findAllTransactions() { return List.of(); }
        @Override public void delete(TransactionId id) {}
    }
}
