package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.automaticexpense.tracker.application.port.in.ProcessTransactionCommandUseCase;
import com.automaticexpense.tracker.domain.TransactionCommandReference;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class TransactionCommandWorkerTest {

    @Test
    void dispatchesOnlyTheDurableCommandReferenceFromAnSqsRecord() {
        CapturingProcessor processor = new CapturingProcessor();
        TransactionCommandWorker worker = new TransactionCommandWorker(processor);
        SQSEvent.SQSMessage message = new SQSEvent.SQSMessage();
        message.setBody("{\"userScopeId\":\"542d240129883c019e106e3b1b2d3f3c\","
            + "\"commandId\":\"client-command-001\"}");
        SQSEvent event = new SQSEvent();
        event.setRecords(java.util.List.of(message));

        worker.handleRequest(event, null);

        assertThat(processor.reference.userScopeId()).isEqualTo("542d240129883c019e106e3b1b2d3f3c");
        assertThat(processor.reference.commandId().value()).isEqualTo("client-command-001");
    }

    private static final class CapturingProcessor implements ProcessTransactionCommandUseCase {
        private TransactionCommandReference reference;

        @Override
        public void process(TransactionCommandReference commandReference) {
            reference = commandReference;
        }
    }
}
