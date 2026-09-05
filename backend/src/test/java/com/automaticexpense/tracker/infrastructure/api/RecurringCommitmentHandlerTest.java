package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.automaticexpense.tracker.application.RecurringCommitmentService;
import com.automaticexpense.tracker.application.port.out.RecurringCommitmentRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.RecurringCommitment;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

class RecurringCommitmentHandlerTest {

    @Test
    void createsAndListsConfirmedCommitmentsAtTheAuthenticatedHttpSeam() {
        RecurringCommitmentHandler handler = new RecurringCommitmentHandler(
            new RecurringCommitmentService(new InMemoryCommitments(), new EmptyTransactions())
        );
        String body = """
            {"name":"Home rent","classification":"RENT","cadence":"MONTHLY",
             "minimumAmount":"25000.00","maximumAmount":"25000.00","currency":"INR",
             "nextPaymentDate":"2026-04-01"}""";

        var created = handler.handleRequest(authenticated("POST", "/v2/recurring-commitments", body), null);
        var listed = handler.handleRequest(authenticated("GET", "/v2/recurring-commitments", null), null);

        assertThat(created.getStatusCode()).isEqualTo(201);
        assertThat(created.getBody()).contains("\"status\":\"CONFIRMED\"", "\"classification\":\"RENT\"");
        assertThat(listed.getStatusCode()).isEqualTo(200);
        assertThat(listed.getBody()).contains("\"commitments\"", "\"name\":\"Home rent\"");
    }

    @Test
    void rejectsARecurringCommitmentRequestWithoutTheVerifiedGatewaySubject() {
        RecurringCommitmentHandler handler = new RecurringCommitmentHandler(
            new RecurringCommitmentService(new InMemoryCommitments(), new EmptyTransactions())
        );

        assertThat(handler.handleRequest(request("GET", "/v2/recurring-commitments"), null).getStatusCode())
            .isEqualTo(401);
    }

    private APIGatewayV2HTTPEvent authenticated(String method, String path, String body) {
        APIGatewayV2HTTPEvent request = request(method, path);
        APIGatewayV2HTTPEvent.RequestContext.Authorizer authorizer =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer();
        APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT jwt =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT();
        jwt.setClaims(java.util.Map.of(
            "sub", "opaque-subject", "email", "commitments@example.com", "email_verified", "true"
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

    private static final class InMemoryCommitments implements RecurringCommitmentRepository {
        private final List<RecurringCommitment> values = new ArrayList<>();
        @Override public void save(RecurringCommitment commitment) {
            values.removeIf(existing -> existing.id().equals(commitment.id()));
            values.add(commitment);
        }
        @Override public Optional<RecurringCommitment> findById(String id) {
            return values.stream().filter(value -> value.id().equals(id)).findFirst();
        }
        @Override public Optional<RecurringCommitment> findByCandidateKey(String key) {
            return values.stream().filter(value -> key.equals(value.candidateKey())).findFirst();
        }
        @Override public List<RecurringCommitment> findAll() { return List.copyOf(values); }
    }

    private static final class EmptyTransactions implements TransactionRepository {
        @Override public void save(Transaction transaction) {}
        @Override public Optional<Transaction> findById(TransactionId id) { return Optional.empty(); }
        @Override public List<Transaction> findByAccountId(AccountId id) { return List.of(); }
        @Override public List<Transaction> findByReconciliationStatus(ReconciliationStatus status) { return List.of(); }
        @Override public List<Transaction> findByAccountIdAndWindow(
            AccountId id, LocalDateTime start, LocalDateTime end
        ) { return List.of(); }
        @Override public List<Transaction> findAllTransactions() { return List.of(); }
        @Override public void delete(TransactionId id) {}
    }
}
