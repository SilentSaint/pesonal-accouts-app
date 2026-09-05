package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.automaticexpense.tracker.application.port.in.FailTransactionCommandUseCase;
import com.automaticexpense.tracker.domain.TransactionCommandReference;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class TransactionCommandDlqHandlerTest {

    @Test
    void marksTheSafeDurableReferenceFailedAfterPrimaryRetriesAreExhausted() {
        CapturingProcessor processor = new CapturingProcessor();
        TransactionCommandDlqHandler handler = new TransactionCommandDlqHandler(processor);
        SQSEvent.SQSMessage message = new SQSEvent.SQSMessage();
        message.setBody("{\"userScopeId\":\"542d240129883c019e106e3b1b2d3f3c\","
            + "\"commandId\":\"client-command-001\"}");
        SQSEvent event = new SQSEvent();
        event.setRecords(List.of(message));

        handler.handleRequest(event, null);

        assertThat(processor.reference.userScopeId()).isEqualTo("542d240129883c019e106e3b1b2d3f3c");
        assertThat(processor.reference.commandId().value()).isEqualTo("client-command-001");
    }

    @Test
    void ignoresMalformedDlqRecordsWithoutChangingAnyCommand() {
        CapturingProcessor processor = new CapturingProcessor();
        TransactionCommandDlqHandler handler = new TransactionCommandDlqHandler(processor);
        SQSEvent.SQSMessage message = new SQSEvent.SQSMessage();
        message.setBody("{\"userScopeId\":\"not-a-safe-scope\",\"commandId\":\"client-command-001\"}");
        SQSEvent event = new SQSEvent();
        event.setRecords(List.of(message));

        handler.handleRequest(event, null);

        assertThat(processor.reference).isNull();
    }

    private static final class CapturingProcessor implements FailTransactionCommandUseCase {
        private TransactionCommandReference reference;

        @Override
        public void failAfterRetryExhaustion(TransactionCommandReference commandReference) {
            reference = commandReference;
        }
    }
}
