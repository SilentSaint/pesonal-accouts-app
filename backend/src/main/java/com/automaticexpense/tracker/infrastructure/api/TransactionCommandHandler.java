package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.application.VendorRuleLearningService;
import com.automaticexpense.tracker.application.port.in.LearnVendorRuleUseCase;
import com.automaticexpense.tracker.application.port.in.ReconciliationReviewUseCase;
import com.automaticexpense.tracker.application.TransactionCommandService;
import com.automaticexpense.tracker.application.port.in.TransactionCommandStatusView;
import com.automaticexpense.tracker.application.port.in.TransactionCommandUseCase;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IngestionSource;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.TransactionType;
import com.automaticexpense.tracker.infrastructure.messaging.SqsFifoTransactionCommandQueue;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbTransactionCommandRepositoryAdapter;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbAccountTransactionRepositoryAdapter;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbVendorRuleRepositoryAdapter;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.core.JsonProcessingException;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.awscore.exception.AwsServiceException;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.sqs.SqsClient;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * HTTP adapter for the staged Java transaction-command Lambda.
 *
 * The adapter receives principal claims only after API Gateway JWT validation.
 */
public final class TransactionCommandHandler
    implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {

    private static final ObjectMapper JSON = new ObjectMapper();
    private static final Logger LOG = Logger.getLogger(TransactionCommandHandler.class.getName());
    private volatile TransactionCommandUseCase commands;
    private volatile LearnVendorRuleUseCase vendorRuleLearning;
    private volatile ReconciliationReviewUseCase reconciliation;

    public TransactionCommandHandler() {
    }

    public TransactionCommandHandler(TransactionCommandUseCase commands) {
        this.commands = commands;
    }

    public TransactionCommandHandler(
        TransactionCommandUseCase commands,
        LearnVendorRuleUseCase vendorRuleLearning
    ) {
        this.commands = commands;
        this.vendorRuleLearning = vendorRuleLearning;
    }

    public TransactionCommandHandler(
        TransactionCommandUseCase commands,
        LearnVendorRuleUseCase vendorRuleLearning,
        ReconciliationReviewUseCase reconciliation
    ) {
        this(commands, vendorRuleLearning);
        this.reconciliation = reconciliation;
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent request, Context context) {
        String path = request.getRawPath();
        String method = request.getRequestContext().getHttp().getMethod();

        if ("GET".equals(method) && "/v2/health".equals(path)) {
            return response(200, "{\"status\":\"ok\",\"module\":\"transaction-command\"}");
        }

        if ("GET".equals(method) && "/v2/reconciliation/review-queue".equals(path)) {
            String email = authenticatedEmail(request);
            if (email == null || email.isBlank()) {
                return response(401, "{\"message\":\"Authentication is required\"}");
            }
            try {
                return reviewQueueResponse(reconciliation(userScopeId(email)).getPendingReconciliationReviews());
            } catch (SdkException exception) {
                return response(503, "{\"message\":\"Reconciliation service is unavailable\"}");
            }
        }

        if ("POST".equals(method) && path != null
            && path.matches("/v2/reconciliation/[^/]+/merge")) {
            String email = authenticatedEmail(request);
            if (email == null || email.isBlank()) {
                return response(401, "{\"message\":\"Authentication is required\"}");
            }
            try {
                JsonNode body = JSON.readTree(request.getBody());
                if (body == null || body.isNull()) {
                    throw new IllegalArgumentException("Request body is required");
                }
                String duplicateId = path.substring(
                    "/v2/reconciliation/".length(), path.length() - "/merge".length()
                );
                return transactionResponse(reconciliation(userScopeId(email)).mergeTransactions(
                    new TransactionId(requiredText(body, "canonicalTransactionId")),
                    new TransactionId(duplicateId)
                ));
            } catch (IllegalArgumentException exception) {
                return response(400, "{\"message\":\"Invalid reconciliation merge\"}");
            } catch (JsonProcessingException exception) {
                return response(400, "{\"message\":\"Invalid JSON request body\"}");
            } catch (SdkException exception) {
                return response(503, "{\"message\":\"Reconciliation service is unavailable\"}");
            }
        }

        if ("PUT".equals(method) && path != null
            && path.matches("/v2/reconciliation/[^/]+/confirm")) {
            String email = authenticatedEmail(request);
            if (email == null || email.isBlank()) {
                return response(401, "{\"message\":\"Authentication is required\"}");
            }
            try {
                JsonNode body = JSON.readTree(request.getBody());
                if (body == null || body.isNull()) {
                    throw new IllegalArgumentException("Request body is required");
                }
                String transactionId = path.substring(
                    "/v2/reconciliation/".length(), path.length() - "/confirm".length()
                );
                return transactionResponse(reconciliation(userScopeId(email)).confirmTransaction(
                    new TransactionId(transactionId), requiredText(body, "categoryId")
                ));
            } catch (IllegalArgumentException exception) {
                return response(400, "{\"message\":\"Invalid reconciliation confirmation\"}");
            } catch (JsonProcessingException exception) {
                return response(400, "{\"message\":\"Invalid JSON request body\"}");
            } catch (SdkException exception) {
                return response(503, "{\"message\":\"Reconciliation service is unavailable\"}");
            }
        }

        if ("PUT".equals(method) && path != null && path.matches("/v2/transactions/[^/]+/category")) {
            String email = authenticatedEmail(request);
            if (email == null || email.isBlank()) {
                return response(401, "{\"message\":\"Authentication is required\"}");
            }
            try {
                JsonNode body = JSON.readTree(request.getBody());
                if (body == null || body.isNull()) {
                    throw new IllegalArgumentException("Request body is required");
                }
                String transactionId = path.substring(
                    "/v2/transactions/".length(), path.length() - "/category".length()
                );
                return vendorRuleResponse(vendorRuleLearning(userScopeId(email)).learn(
                    new TransactionId(transactionId),
                    requiredText(body, "categoryId"),
                    nullableText(body, "subCategory"),
                    nullableText(body, "payeeNickname")
                ));
            } catch (IllegalArgumentException exception) {
                if (exception.getMessage() != null
                    && exception.getMessage().startsWith("Transaction not found:")) {
                    return response(409,
                        "{\"message\":\"Transaction is not available for categorization. Rescan Gmail and confirm it before saving a category rule.\"}"
                    );
                }
                return response(400, "{\"message\":\"Invalid category correction\"}");
            } catch (JsonProcessingException exception) {
                return response(400, "{\"message\":\"Invalid JSON request body\"}");
            } catch (SdkException exception) {
                return response(503, "{\"message\":\"Vendor rule service is unavailable\"}");
            }
        }

        if ("POST".equals(method) && "/v2/transactions".equals(path)) {
            String email = authenticatedEmail(request);
            if (email == null || email.isBlank()) {
                return response(401, "{\"message\":\"Authentication is required\"}");
            }

            try {
                JsonNode body = JSON.readTree(request.getBody());
                if (body == null || body.isNull()) {
                    throw new IllegalArgumentException("Request body is required");
                }
                String commandId = requiredText(body, "id");
                TransactionCommandStatusView status = commands().submit(
                    userScopeId(email),
                    new TransactionId(commandId),
                    new IngestTransactionCommand(
                        new Money(new BigDecimal(requiredText(body, "amount")),
                            body.path("currency").asText("INR")),
                        TransactionType.valueOf(requiredText(body, "type")),
                        timestamp(body.path("timestamp")),
                        body.path("merchantName").asText("Unknown"),
                        new AccountId(requiredText(body, "accountId")),
                        nullableText(body, "categoryId"),
                        IngestionSource.valueOf(body.path("ingestionSource").asText("MANUAL")),
                        nullableText(body, "subCategory"),
                        nullableMoney(body, "netPersonalExpense", body.path("currency").asText("INR")),
                        nullableText(body, "accountMask"),
                        nullableText(body, "referenceNumber"),
                        nullableText(body, "rawSnippet"),
                        nullableText(body, "transferCounterpartMask")
                    )
                );
                logCommandSubmission(request, commandId, status.status().name());
                return commandResponse(202, status);
            } catch (IllegalArgumentException exception) {
                return response(400, "{\"message\":\"Invalid transaction command\"}");
            } catch (JsonProcessingException exception) {
                return response(400, "{\"message\":\"Invalid JSON request body\"}");
            } catch (SdkException exception) {
                logServiceFailure("transaction-command-submit", request, exception);
                return response(503, "{\"message\":\"Transaction command service is unavailable\"}");
            }
        }

        if ("GET".equals(method) && path != null && path.matches("/v2/transactions/[^/]+/status")) {
            String email = authenticatedEmail(request);
            if (email == null || email.isBlank()) {
                return response(401, "{\"message\":\"Authentication is required\"}");
            }
            try {
                String commandId = path.substring("/v2/transactions/".length(), path.length() - "/status".length());
                return commands().status(userScopeId(email), new TransactionId(commandId))
                    .map(status -> commandResponse(200, status))
                    .orElseGet(() -> response(404, "{\"message\":\"Transaction command not found\"}"));
            } catch (IllegalArgumentException exception) {
                return response(400, "{\"message\":\"Invalid transaction command\"}");
            } catch (SdkException exception) {
                return response(503, "{\"message\":\"Transaction command service is unavailable\"}");
            }
        }

        return response(404, "{\"message\":\"Route not found\"}");
    }

    private APIGatewayV2HTTPResponse commandResponse(int statusCode, TransactionCommandStatusView status) {
        Map<String, String> payload = new LinkedHashMap<>();
        payload.put("id", status.id().value());
        payload.put("status", status.status().name());
        if (status.failureReason() != null) {
            payload.put("failureReason", status.failureReason());
        }

        try {
            return response(statusCode, JSON.writeValueAsString(payload));
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to serialize transaction command status", exception);
        }
    }

    private APIGatewayV2HTTPResponse vendorRuleResponse(
        com.automaticexpense.tracker.domain.Transaction transaction
    ) {
        Map<String, String> payload = new LinkedHashMap<>();
        payload.put("id", transaction.id().value());
        payload.put("categoryId", transaction.categoryId());
        if (transaction.subCategory() != null) {
            payload.put("subCategory", transaction.subCategory());
        }
        try {
            return response(200, JSON.writeValueAsString(payload));
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to serialize vendor rule correction", exception);
        }
    }

    private APIGatewayV2HTTPResponse reviewQueueResponse(
        java.util.List<com.automaticexpense.tracker.domain.ReconciliationReview> reviews
    ) {
        try {
            return response(200, JSON.writeValueAsString(
                reviews.stream().map(review -> {
                    Map<String, Object> payload = new LinkedHashMap<>();
                    payload.put("candidate", transactionPayload(review.candidate()));
                    if (review.canonical() != null) {
                        payload.put("canonical", transactionPayload(review.canonical()));
                    }
                    return payload;
                }).toList()
            ));
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to serialize reconciliation review queue", exception);
        }
    }

    private APIGatewayV2HTTPResponse transactionResponse(
        com.automaticexpense.tracker.domain.Transaction transaction
    ) {
        try {
            return response(200, JSON.writeValueAsString(transactionPayload(transaction)));
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to serialize reconciliation transaction", exception);
        }
    }

    private Map<String, Object> transactionPayload(
        com.automaticexpense.tracker.domain.Transaction transaction
    ) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("id", transaction.id().value());
        payload.put("amount", transaction.amount().amount());
        payload.put("currency", transaction.amount().currency());
        payload.put("type", transaction.type().name());
        payload.put("merchantName", transaction.merchantName());
        payload.put("accountId", transaction.accountId().value());
        payload.put("categoryId", transaction.categoryId());
        payload.put("subCategory", transaction.subCategory());
        payload.put("ingestionSource", transaction.ingestionSource().name());
        payload.put("ingestionSources", transaction.ingestionSources().stream().map(Enum::name).sorted().toList());
        payload.put("reconciliationStatus", transaction.reconciliationStatus().name());
        payload.put("timestamp", transaction.timestamp().atOffset(ZoneOffset.UTC).toInstant().toEpochMilli());
        payload.put("netPersonalExpense", transaction.netPersonalExpense().amount());
        payload.put("accountMask", transaction.accountMask());
        payload.put("referenceNumber", transaction.referenceNumber());
        payload.put("rawSnippet", transaction.rawSnippet());
        payload.put("transferCounterpartMask", transaction.transferCounterpartMask());
        if (transaction.potentialDuplicateOfTransactionId() != null) {
            payload.put("potentialDuplicateOfTransactionId",
                transaction.potentialDuplicateOfTransactionId().value());
        }
        return payload;
    }

    private TransactionCommandUseCase commands() {
        TransactionCommandUseCase configured = commands;
        if (configured == null) {
            synchronized (this) {
                configured = commands;
                if (configured == null) {
                    configured = new TransactionCommandService(
                        new AwsDynamoDbTransactionCommandRepositoryAdapter(
                            DynamoDbClient.create(), requiredEnvironmentStatic("TABLE_NAME")
                        ),
                        new SqsFifoTransactionCommandQueue(
                            SqsClient.create(), requiredEnvironmentStatic("TRANSACTION_COMMAND_QUEUE_URL")
                        )
                    );
                    commands = configured;
                }
            }
        }
        return configured;
    }

    private LearnVendorRuleUseCase vendorRuleLearning(String userScopeId) {
        LearnVendorRuleUseCase configured = vendorRuleLearning;
        if (configured != null) {
            return configured;
        }
        String tableName = requiredEnvironmentStatic("TABLE_NAME");
        DynamoDbClient client = DynamoDbClient.create();
        return new VendorRuleLearningService(
            new AwsDynamoDbAccountTransactionRepositoryAdapter(client, tableName, userScopeId),
            new AwsDynamoDbVendorRuleRepositoryAdapter(client, tableName, userScopeId)
        );
    }

    private ReconciliationReviewUseCase reconciliation(String userScopeId) {
        ReconciliationReviewUseCase configured = reconciliation;
        if (configured != null) {
            return configured;
        }
        String tableName = requiredEnvironmentStatic("TABLE_NAME");
        DynamoDbClient client = DynamoDbClient.create();
        return new com.automaticexpense.tracker.application.IngestTransactionService(
            new AwsDynamoDbAccountTransactionRepositoryAdapter(client, tableName, userScopeId),
            new AwsDynamoDbVendorRuleRepositoryAdapter(client, tableName, userScopeId)
        );
    }

    private APIGatewayV2HTTPResponse response(int statusCode, String body) {
        return APIGatewayV2HTTPResponse.builder()
            .withStatusCode(statusCode)
            .withHeaders(Map.of("Content-Type", "application/json"))
            .withBody(body)
            .build();
    }

    private void logServiceFailure(
        String operation,
        APIGatewayV2HTTPEvent request,
        SdkException exception
    ) {
        String requestId = request.getRequestContext() == null
            ? "unknown"
            : String.valueOf(request.getRequestContext().getRequestId());
        if (exception instanceof AwsServiceException serviceException) {
            LOG.log(
                Level.WARNING,
                "event=command_submission outcome=dependency_failure operation={0} requestId={1} exception={2} awsError={3} status={4} message={5}",
                new Object[] {
                    operation,
                    requestId,
                    exception.getClass().getSimpleName(),
                    serviceException.awsErrorDetails() == null
                        ? "unknown"
                        : serviceException.awsErrorDetails().errorCode(),
                    serviceException.statusCode(),
                    safeLogMessage(serviceException.getMessage())
                }
            );
            return;
        }
        LOG.log(
            Level.WARNING,
            "event=command_submission outcome=client_failure operation={0} requestId={1} exception={2}",
            new Object[] {operation, requestId, exception.getClass().getSimpleName()}
        );
    }

    private String safeLogMessage(String message) {
        if (message == null || message.isBlank()) {
            return "unknown";
        }
        String normalized = message.replaceAll("[\\r\\n\\t]+", " ")
            .replaceAll("\\s{2,}", " ")
            .trim();
        return normalized.substring(0, Math.min(normalized.length(), 240));
    }

    private void logCommandSubmission(
        APIGatewayV2HTTPEvent request,
        String commandId,
        String status
    ) {
        String requestId = request.getRequestContext() == null
            ? "unknown"
            : String.valueOf(request.getRequestContext().getRequestId());
        LOG.log(
            Level.INFO,
            "event=command_submission outcome=accepted requestId={0} commandId={1} status={2}",
            new Object[] {requestId, commandId, status}
        );
    }

    private String authenticatedEmail(APIGatewayV2HTTPEvent request) {
        if (request.getRequestContext() == null
            || request.getRequestContext().getAuthorizer() == null
            || request.getRequestContext().getAuthorizer().getJwt() == null
            || request.getRequestContext().getAuthorizer().getJwt().getClaims() == null) {
            return null;
        }
        Map<String, String> claims = request.getRequestContext().getAuthorizer().getJwt().getClaims();
        if (!"true".equalsIgnoreCase(claims.get("email_verified"))) {
            return null;
        }
        return claims.get("email");
    }

    private String requiredText(JsonNode body, String field) {
        String value = nullableText(body, field);
        if (value == null) {
            throw new IllegalArgumentException(field + " is required");
        }
        return value;
    }

    private String nullableText(JsonNode body, String field) {
        String value = body.path(field).asText(null);
        return value == null || value.isBlank() ? null : value;
    }

    private Money nullableMoney(JsonNode body, String field, String currency) {
        String value = nullableText(body, field);
        return value == null ? null : new Money(new BigDecimal(value), currency);
    }

    private LocalDateTime timestamp(JsonNode value) {
        if (value.isIntegralNumber()) {
            return Instant.ofEpochMilli(value.longValue()).atOffset(ZoneOffset.UTC).toLocalDateTime();
        }
        String timestamp = value.asText(null);
        if (timestamp == null || timestamp.isBlank()) {
            throw new IllegalArgumentException("timestamp is required");
        }
        try {
            return Instant.parse(timestamp).atOffset(ZoneOffset.UTC).toLocalDateTime();
        } catch (DateTimeParseException ignored) {
            return LocalDateTime.parse(timestamp);
        }
    }

    private static String requiredEnvironmentStatic(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(name + " is not configured");
        }
        return value;
    }

    private String userScopeId(String email) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(email.toLowerCase().trim().getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest).substring(0, 32);
        } catch (Exception exception) {
            throw new IllegalStateException("Unable to derive authenticated user scope", exception);
        }
    }
}
