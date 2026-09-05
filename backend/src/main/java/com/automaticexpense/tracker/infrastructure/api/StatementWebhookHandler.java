package com.automaticexpense.tracker.infrastructure.api;

import com.automaticexpense.tracker.application.port.in.IngestStatementWebhookUseCase;
import com.automaticexpense.tracker.application.port.in.StatementIngestionSummary;
import com.automaticexpense.tracker.domain.IngestionSource;

import java.util.Objects;

public class StatementWebhookHandler {

    private final IngestStatementWebhookUseCase useCase;

    public StatementWebhookHandler(IngestStatementWebhookUseCase useCase) {
        this.useCase = Objects.requireNonNull(useCase, "useCase cannot be null");
    }

    public WebhookResponse handleWebhook(String payload, String sourceHeader) {
        if (payload == null || payload.isBlank()) {
            return new WebhookResponse(400, "Payload cannot be empty", null);
        }

        try {
            IngestionSource source = (sourceHeader != null && sourceHeader.equalsIgnoreCase("SMS"))
                ? IngestionSource.SMS
                : IngestionSource.EMAIL;

            StatementIngestionSummary summary = useCase.ingestStatementPayload(payload, source);
            return new WebhookResponse(200, "Statement processed successfully", summary);
        } catch (Exception e) {
            return new WebhookResponse(500, "Error processing statement: " + e.getMessage(), null);
        }
    }

    public record WebhookResponse(int statusCode, String message, StatementIngestionSummary summary) {}
}
