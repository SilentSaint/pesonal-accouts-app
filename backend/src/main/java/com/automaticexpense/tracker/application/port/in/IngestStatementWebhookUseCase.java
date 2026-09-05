package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.IngestionSource;

public interface IngestStatementWebhookUseCase {
    StatementIngestionSummary ingestStatementPayload(String rawPayload, IngestionSource source);
}
