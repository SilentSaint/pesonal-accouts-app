package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.automaticexpense.tracker.application.TransactionCommandProcessor;
import com.automaticexpense.tracker.application.port.in.ProcessTransactionCommandUseCase;
import com.automaticexpense.tracker.infrastructure.messaging.SqsTransactionCommandReferenceParser;
import com.automaticexpense.tracker.infrastructure.messaging.AwsApiGatewayWebSocketEventPublisher;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbTransactionCommandRepositoryAdapter;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.apigatewaymanagementapi.ApiGatewayManagementApiClient;

import java.util.Objects;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * FIFO worker. Batch size is one so a failed record is retried without reordering its user group.
 */
public final class TransactionCommandWorker implements RequestHandler<SQSEvent, Void> {
    private static final Logger LOG = Logger.getLogger(TransactionCommandWorker.class.getName());
    private final ProcessTransactionCommandUseCase processor;

    public TransactionCommandWorker() {
        this(new TransactionCommandProcessor(
            new AwsDynamoDbTransactionCommandRepositoryAdapter(
                DynamoDbClient.create(), requiredEnvironment("TABLE_NAME")
            ),
            new DynamoDbTransactionIngestionExecutor(
                DynamoDbClient.create(), requiredEnvironment("TABLE_NAME")
            ),
            new AwsApiGatewayWebSocketEventPublisher(
                DynamoDbClient.create(),
                ApiGatewayManagementApiClient.builder()
                    .endpointOverride(java.net.URI.create(requiredEnvironment("WEBSOCKET_MANAGEMENT_ENDPOINT")))
                    .build(),
                requiredEnvironment("TABLE_NAME")
            )
        ));
    }

    public TransactionCommandWorker(ProcessTransactionCommandUseCase processor) {
        this.processor = Objects.requireNonNull(processor, "processor cannot be null");
    }

    @Override
    public Void handleRequest(SQSEvent event, Context context) {
        if (event == null || event.getRecords() == null) {
            throw new IllegalArgumentException("SQS event records are required");
        }
        String requestId = context == null || context.getAwsRequestId() == null
            ? "unknown"
            : context.getAwsRequestId();
        LOG.log(Level.INFO, "event=command_worker_start outcome=started requestId={0} recordCount={1}",
            new Object[] {requestId, event.getRecords().size()});
        for (SQSEvent.SQSMessage message : event.getRecords()) {
            var reference = SqsTransactionCommandReferenceParser.parse(message.getBody());
            LOG.log(Level.INFO,
                "event=command_processing outcome=started requestId={0} commandId={1}",
                new Object[] {requestId, reference.commandId().value()});
            try {
                processor.process(reference);
                LOG.log(Level.INFO,
                    "event=command_processing outcome=completed requestId={0} commandId={1}",
                    new Object[] {requestId, reference.commandId().value()});
            } catch (RuntimeException exception) {
                LOG.log(Level.WARNING,
                    "event=command_processing outcome=failed requestId={0} commandId={1} exception={2}",
                    new Object[] {requestId, reference.commandId().value(), exception.getClass().getSimpleName()});
                throw exception;
            }
        }
        LOG.log(Level.INFO, "event=command_worker_complete outcome=completed requestId={0}", requestId);
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
