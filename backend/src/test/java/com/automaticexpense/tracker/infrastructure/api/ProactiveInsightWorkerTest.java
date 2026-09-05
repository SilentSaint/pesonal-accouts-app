package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.automaticexpense.tracker.application.port.in.RefreshFinancialProjectionsRequest;
import com.automaticexpense.tracker.application.port.in.RefreshFinancialProjectionsResult;
import com.automaticexpense.tracker.application.port.in.RefreshFinancialProjectionsUseCase;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class ProactiveInsightWorkerTest {

    @Test
    void refreshesTheAffectedUsersPersistedProjectionsFromABoundedQueueMessage() {
        CapturingUseCase useCase = new CapturingUseCase();
        ProactiveInsightWorker worker = new ProactiveInsightWorker(useCase);
        SQSEvent.SQSMessage message = new SQSEvent.SQSMessage();
        message.setBody("""
            {"userId":"scope-a","asOf":"2026-08-31T18:30:00Z","timezone":"Asia/Kolkata","currency":"INR"}
            """);
        SQSEvent event = new SQSEvent();
        event.setRecords(List.of(message));

        worker.handleRequest(event, null);

        assertThat(useCase.request).isEqualTo(new RefreshFinancialProjectionsRequest(
            "scope-a", Instant.parse("2026-08-31T18:30:00Z"), ZoneId.of("Asia/Kolkata"), "INR"
        ));
    }

    private static final class CapturingUseCase implements RefreshFinancialProjectionsUseCase {
        private RefreshFinancialProjectionsRequest request;

        @Override
        public RefreshFinancialProjectionsResult refresh(RefreshFinancialProjectionsRequest request) {
            this.request = request;
            return new RefreshFinancialProjectionsResult(List.of(), 0);
        }
    }
}
