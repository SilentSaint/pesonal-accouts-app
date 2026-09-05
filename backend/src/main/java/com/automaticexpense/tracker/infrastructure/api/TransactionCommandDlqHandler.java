package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.automaticexpense.tracker.application.TransactionCommandDlqProcessor;
import com.automaticexpense.tracker.application.port.in.FailTransactionCommandUseCase;
import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.automaticexpense.tracker.infrastructure.messaging.SqsTransactionCommandReferenceParser;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbTransactionCommandRepositoryAdapter;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.util.Objects;

/**
 * Marks only processing commands failed after the primary FIFO worker exhausts SQS retries.
 */
public final class TransactionCommandDlqHandler implements RequestHandler<SQSEvent, Void> {
    private final FailTransactionCommandUseCase processor;

    public TransactionCommandDlqHandler() {
        this(new TransactionCommandDlqProcessor(new AwsDynamoDbTransactionCommandRepositoryAdapter(
            DynamoDbClient.create(), requiredEnvironment("TABLE_NAME")
        )));
    }

    public TransactionCommandDlqHandler(FailTransactionCommandUseCase processor) {
        this.processor = Objects.requireNonNull(processor, "processor cannot be null");
    }

    @Override
    public Void handleRequest(SQSEvent event, Context context) {
        if (event == null || event.getRecords() == null) {
            throw new IllegalArgumentException("SQS event records are required");
        }
        for (SQSEvent.SQSMessage message : event.getRecords()) {
            TransactionCommandReference reference;
            try {
                reference = SqsTransactionCommandReferenceParser.parse(message.getBody());
            } catch (IllegalArgumentException ignored) {
                // An untrusted malformed DLQ record cannot identify a command to change.
                continue;
            }
            processor.failAfterRetryExhaustion(reference);
        }
        return null;
    }

    private static String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(name + " is not configured");
        }
        return value;
    }
}
