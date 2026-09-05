package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.application.port.in.LearnVendorRuleUseCase;
import com.automaticexpense.tracker.application.port.in.TransactionCommandStatusView;
import com.automaticexpense.tracker.application.port.in.TransactionCommandUseCase;
import com.automaticexpense.tracker.application.port.in.ReconciliationReviewUseCase;
import com.automaticexpense.tracker.domain.IngestionSource;
import com.automaticexpense.tracker.domain.TransactionCommandStatus;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.TransactionType;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.ReconciliationReview;
import org.junit.jupiter.api.Test;

import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

class TransactionCommandHandlerTest {

    @Test
    void exposesTheJavaTransactionModuleHealthAtItsPublicSeam() {
        TransactionCommandHandler handler = new TransactionCommandHandler();

        var response = handler.handleRequest(request("GET", "/v2/health", Map.of()), null);

        assertThat(response.getStatusCode()).isEqualTo(200);
        assertThat(response.getBody()).isEqualTo(
            "{\"status\":\"ok\",\"module\":\"transaction-command\"}"
        );
    }

    @Test
    void rejectsUnauthenticatedTransactionCommandsBeforeTheyReachTheUseCase() {
        TransactionCommandHandler handler = new TransactionCommandHandler();

        var response = handler.handleRequest(request("POST", "/v2/transactions", Map.of()), null);

        assertThat(response.getStatusCode()).isEqualTo(401);
        assertThat(response.getBody()).isEqualTo("{\"message\":\"Authentication is required\"}");
    }

    @Test
    void rejectsUnauthenticatedCategoryCorrectionsBeforeTheyReachVendorLearning() {
        TransactionCommandHandler handler = new TransactionCommandHandler();

        var response = handler.handleRequest(request(
            "PUT", "/v2/transactions/txn-vendor-rule-001/category", Map.of()
        ), null);

        assertThat(response.getStatusCode()).isEqualTo(401);
        assertThat(response.getBody()).isEqualTo("{\"message\":\"Authentication is required\"}");
    }

    @Test
    void explainsWhenCategoryLearningTargetsAnUnpersistedTransaction() {
        LearnVendorRuleUseCase learning = (id, category, subCategory, nickname) -> {
            throw new IllegalArgumentException("Transaction not found: " + id.value());
        };
        TransactionCommandHandler handler =
            new TransactionCommandHandler(recordingCommands(), learning);

        var response = handler.handleRequest(authenticatedRequest(
            "PUT",
            "/v2/transactions/txn-gmail-missing-001/category",
            "{\"categoryId\":\"Food & Dining\"}"
        ), null);

        assertThat(response.getStatusCode()).isEqualTo(409);
        assertThat(response.getBody()).isEqualTo(
            "{\"message\":\"Transaction is not available for categorization. "
                + "Rescan Gmail and confirm it before saving a category rule.\"}"
        );
    }

    @Test
    void rejectsTransactionCommandsWithAnUnverifiedGatewayEmailClaim() {
        TransactionCommandHandler handler = new TransactionCommandHandler();

        var response = handler.handleRequest(authenticatedRequest(
            "POST",
            "/v2/transactions",
            "{\"id\":\"client-command-001\",\"amount\":\"125.00\",\"type\":\"DEBIT\","
                + "\"timestamp\":\"2026-08-29T06:00:00Z\",\"accountId\":\"acc-1001\"}",
            "false"
        ), null);

        assertThat(response.getStatusCode()).isEqualTo(401);
        assertThat(response.getBody()).isEqualTo("{\"message\":\"Authentication is required\"}");
    }

    @Test
    void acceptsAnAuthenticatedTransactionAsAPendingDurableCommand() {
        TransactionCommandHandler handler = new TransactionCommandHandler(recordingCommands());

        var response = handler.handleRequest(authenticatedRequest(
            "POST",
            "/v2/transactions",
            "{\"id\":\"client-command-001\",\"amount\":\"125.00\",\"type\":\"DEBIT\","
                + "\"timestamp\":\"2026-08-29T06:00:00Z\",\"accountId\":\"acc-1001\"}"
        ), null);

        assertThat(response.getStatusCode()).isEqualTo(202);
        assertThat(response.getBody()).isEqualTo(
            "{\"id\":\"client-command-001\",\"status\":\"PENDING\"}"
        );
    }

    @Test
    void exposesTheAuthenticatedUsersDurableReconciliationQueueAndMergeAction() {
        Transaction canonical = transaction("txn-sms-001", IngestionSource.SMS);
        Transaction candidate = transaction("txn-email-001", IngestionSource.EMAIL)
            .withPotentialDuplicateOf(canonical.id());
        AtomicReference<TransactionId> mergedCanonical = new AtomicReference<>();
        AtomicReference<TransactionId> mergedCandidate = new AtomicReference<>();
        ReconciliationReviewUseCase reviews = new ReconciliationReviewUseCase() {
            @Override
            public java.util.List<Transaction> getPendingReviewTransactions() {
                return java.util.List.of(candidate);
            }

            @Override
            public java.util.List<ReconciliationReview> getPendingReconciliationReviews() {
                return java.util.List.of(new ReconciliationReview(candidate, canonical));
            }

            @Override
            public Transaction confirmTransaction(TransactionId id, String categoryId) {
                return candidate.confirmedAsSeparate(categoryId);
            }

            @Override
            public Transaction mergeTransactions(TransactionId canonicalId, TransactionId candidateId) {
                mergedCanonical.set(canonicalId);
                mergedCandidate.set(candidateId);
                return canonical.enrichedWith(IngestionSource.EMAIL);
            }
        };
        TransactionCommandHandler handler =
            new TransactionCommandHandler(recordingCommands(), null, reviews);

        var queueResponse = handler.handleRequest(authenticatedRequest(
            "GET", "/v2/reconciliation/review-queue", null
        ), null);
        var mergeResponse = handler.handleRequest(authenticatedRequest(
            "POST", "/v2/reconciliation/txn-email-001/merge",
            "{\"canonicalTransactionId\":\"txn-sms-001\"}"
        ), null);

        assertThat(queueResponse.getStatusCode()).isEqualTo(200);
        assertThat(queueResponse.getBody()).contains(
            "\"candidate\"", "\"canonical\"", "\"potentialDuplicateOfTransactionId\":\"txn-sms-001\""
        );
        assertThat(mergeResponse.getStatusCode()).isEqualTo(200);
        assertThat(mergedCanonical.get()).isEqualTo(canonical.id());
        assertThat(mergedCandidate.get()).isEqualTo(candidate.id());
        assertThat(mergeResponse.getBody()).contains("\"ingestionSources\":[\"EMAIL\",\"SMS\"]");
    }

    @Test
    void acceptsTheFrontendTransactionJsonWithANumericEpochTimestamp() {
        AtomicReference<IngestTransactionCommand> received = new AtomicReference<>();
        TransactionCommandHandler handler = new TransactionCommandHandler(recordingCommands(received));

        var response = handler.handleRequest(authenticatedRequest(
            "POST",
            "/v2/transactions",
            "{\"id\":\"txn-manual-1724911200000\",\"amount\":125.00,\"currency\":\"INR\","
                + "\"type\":\"DEBIT\",\"merchantName\":\"Coffee Shop\",\"accountId\":\"acc-1001\","
                + "\"categoryId\":null,\"ingestionSource\":\"MANUAL\",\"reconciliationStatus\":\"CONFIRMED\","
                + "\"timestamp\":1724911200000,\"netPersonalExpense\":125.00,"
                + "\"accountMask\":\"•••• 1001\",\"referenceNumber\":null,\"rawSnippet\":null}"
        ), null);

        assertThat(response.getStatusCode()).isEqualTo(202);
        assertThat(received.get().amount().amount()).isEqualByComparingTo("125.00");
        assertThat(received.get().timestamp())
            .isEqualTo(java.time.LocalDateTime.of(2024, 8, 29, 6, 0));
        assertThat(received.get().merchantName()).isEqualTo("Coffee Shop");
        assertThat(received.get().ingestionSource())
            .isEqualTo(com.automaticexpense.tracker.domain.IngestionSource.MANUAL);
    }

    @Test
    void forwardsEveryEditedReviewFieldToTheDurableTransactionCommand() {
        AtomicReference<IngestTransactionCommand> received = new AtomicReference<>();
        TransactionCommandHandler handler = new TransactionCommandHandler(recordingCommands(received));

        var response = handler.handleRequest(authenticatedRequest(
            "POST",
            "/v2/transactions",
            "{\"id\":\"txn-review-00000001\",\"amount\":913.42,\"currency\":\"INR\","
                + "\"type\":\"DEBIT\",\"merchantName\":\"Green Market\",\"accountId\":\"acc-1234\","
                + "\"categoryId\":\"Groceries\",\"subCategory\":\"Fruits & Vegetables\","
                + "\"ingestionSource\":\"MANUAL\",\"reconciliationStatus\":\"CONFIRMED\","
                + "\"timestamp\":1787983200000,\"netPersonalExpense\":900.00,"
                + "\"accountMask\":\"•••• 1234\",\"referenceNumber\":\"upi-12345678\","
                + "\"rawSnippet\":\"edited receipt\",\"transferCounterpartMask\":\"•••• 9876\"}"
        ), null);

        assertThat(response.getStatusCode()).isEqualTo(202);
        assertThat(received.get().amount().amount()).isEqualByComparingTo("913.42");
        assertThat(received.get().type()).isEqualTo(TransactionType.DEBIT);
        assertThat(received.get().timestamp())
            .isEqualTo(java.time.LocalDateTime.of(2026, 8, 29, 6, 0));
        assertThat(received.get().merchantName()).isEqualTo("Green Market");
        assertThat(received.get().accountId().value()).isEqualTo("acc-1234");
        assertThat(received.get().categoryId()).isEqualTo("Groceries");
        assertThat(received.get().subCategory()).isEqualTo("Fruits & Vegetables");
        assertThat(received.get().ingestionSource()).isEqualTo(IngestionSource.MANUAL);
        assertThat(received.get().netPersonalExpense().amount()).isEqualByComparingTo("900.00");
        assertThat(received.get().accountMask()).isEqualTo("•••• 1234");
        assertThat(received.get().referenceNumber()).isEqualTo("upi-12345678");
        assertThat(received.get().rawSnippet()).isEqualTo("edited receipt");
        assertThat(received.get().transferCounterpartMask()).isEqualTo("•••• 9876");
    }

    @Test
    void exposesOnlyTheAuthenticatedUsersCommandStatus() {
        TransactionCommandHandler handler = new TransactionCommandHandler(new TransactionCommandUseCase() {
            @Override
            public TransactionCommandStatusView submit(
                String userScopeId,
                TransactionId commandId,
                IngestTransactionCommand command
            ) {
                throw new AssertionError("submission was not expected");
            }

            @Test
            void acceptsAnAuthenticatedCategoryCorrectionAndForwardsItToVendorLearning() {
                AtomicReference<TransactionId> transactionId = new AtomicReference<>();
                AtomicReference<String> category = new AtomicReference<>();
                AtomicReference<String> subCategory = new AtomicReference<>();
                AtomicReference<String> nickname = new AtomicReference<>();
                LearnVendorRuleUseCase learning = (id, categoryId, subCategoryId, payeeNickname) -> {
                    transactionId.set(id);
                    category.set(categoryId);
                    subCategory.set(subCategoryId);
                    nickname.set(payeeNickname);
                    return new Transaction(
                        id, Money.of("150.00", "INR"), TransactionType.DEBIT,
                        java.time.LocalDateTime.of(2026, 8, 29, 10, 0), "Saira Banu",
                        new AccountId("acc-7788"), categoryId, subCategoryId, IngestionSource.SMS,
                        ReconciliationStatus.CONFIRMED, Money.of("150.00", "INR"),
                        null, null, null, null
                    );
                };
                TransactionCommandHandler handler = new TransactionCommandHandler(recordingCommands(), learning);

                var response = handler.handleRequest(authenticatedRequest(
                    "PUT",
                    "/v2/transactions/txn-vendor-rule-001/category",
                    "{\"categoryId\":\"Food & Dining\",\"subCategory\":\"Tea & Snacks\","
                        + "\"payeeNickname\":\"Saira's tea stall\"}"
                ), null);

                assertThat(response.getStatusCode()).isEqualTo(200);
                assertThat(response.getBody()).isEqualTo(
                    "{\"id\":\"txn-vendor-rule-001\",\"categoryId\":\"Food & Dining\","
                        + "\"subCategory\":\"Tea & Snacks\"}"
                );
                assertThat(transactionId.get().value()).isEqualTo("txn-vendor-rule-001");
                assertThat(category.get()).isEqualTo("Food & Dining");
                assertThat(subCategory.get()).isEqualTo("Tea & Snacks");
                assertThat(nickname.get()).isEqualTo("Saira's tea stall");
            }

            @Override
            public Optional<TransactionCommandStatusView> status(String userScopeId, TransactionId commandId) {
                assertThat(userScopeId).isEqualTo("542d240129883c019e106e3b1b2d3f3c");
                assertThat(commandId.value()).isEqualTo("client-command-001");
                return Optional.of(new TransactionCommandStatusView(
                    commandId, TransactionCommandStatus.COMPLETED, null
                ));
            }
        });

        var response = handler.handleRequest(authenticatedRequest(
            "GET", "/v2/transactions/client-command-001/status", null
        ), null);

        assertThat(response.getStatusCode()).isEqualTo(200);
        assertThat(response.getBody()).isEqualTo(
            "{\"id\":\"client-command-001\",\"status\":\"COMPLETED\"}"
        );
    }

    private TransactionCommandUseCase recordingCommands() {
        return recordingCommands(null);
    }

    private Transaction transaction(String id, IngestionSource source) {
        return new Transaction(
            new TransactionId(id),
            Money.of("125.00", "INR"),
            TransactionType.DEBIT,
            java.time.LocalDateTime.of(2026, 8, 29, 10, 0),
            "Coffee Shop",
            new AccountId("acc-1001"),
            "Food & Dining",
            source,
            ReconciliationStatus.NEEDS_REVIEW,
            Money.of("125.00", "INR")
        );
    }

    private TransactionCommandUseCase recordingCommands(
        AtomicReference<IngestTransactionCommand> received
    ) {
        return new TransactionCommandUseCase() {
            @Override
            public TransactionCommandStatusView submit(
                String userScopeId,
                TransactionId commandId,
                IngestTransactionCommand command
            ) {
                assertThat(userScopeId).isEqualTo("542d240129883c019e106e3b1b2d3f3c");
                if (received != null) {
                    received.set(command);
                }
                return new TransactionCommandStatusView(
                    commandId, TransactionCommandStatus.PENDING, null
                );
            }

            @Override
            public Optional<TransactionCommandStatusView> status(
                String userScopeId,
                TransactionId commandId
            ) {
                return Optional.empty();
            }
        };
    }

    private APIGatewayV2HTTPEvent request(
        String method,
        String path,
        Map<String, String> headers
    ) {
        APIGatewayV2HTTPEvent.RequestContext.Http http =
            new APIGatewayV2HTTPEvent.RequestContext.Http();
        http.setMethod(method);

        APIGatewayV2HTTPEvent.RequestContext context =
            new APIGatewayV2HTTPEvent.RequestContext();
        context.setHttp(http);

        APIGatewayV2HTTPEvent request = new APIGatewayV2HTTPEvent();
        request.setRawPath(path);
        request.setHeaders(headers);
        request.setRequestContext(context);
        return request;
    }

    private APIGatewayV2HTTPEvent authenticatedRequest(String method, String path, String body) {
        return authenticatedRequest(method, path, body, "true");
    }

    private APIGatewayV2HTTPEvent authenticatedRequest(
        String method,
        String path,
        String body,
        String emailVerified
    ) {
        APIGatewayV2HTTPEvent request = request(method, path, Map.of());
        APIGatewayV2HTTPEvent.RequestContext.Authorizer authorizer =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer();
        APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT jwt =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT();
        jwt.setClaims(Map.of("email", "person@example.com", "email_verified", emailVerified));
        authorizer.setJwt(jwt);
        request.getRequestContext().setAuthorizer(authorizer);
        request.setBody(body);
        return request;
    }
}
