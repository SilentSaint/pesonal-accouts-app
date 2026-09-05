package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.automaticexpense.tracker.domain.TransactionId;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.UpdateItemRequest;

import java.lang.reflect.Proxy;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

class AwsDynamoDbTransactionCommandRepositoryAdapterTest {

    @Test
    void marksACommandEnqueuedWithoutSendingAnEmptyExpressionNameMap() {
        AtomicReference<UpdateItemRequest> updated = new AtomicReference<>();
        DynamoDbClient client = (DynamoDbClient) Proxy.newProxyInstance(
            getClass().getClassLoader(), new Class<?>[] {DynamoDbClient.class},
            (proxy, method, arguments) -> {
                if (method.getName().equals("updateItem")) {
                    updated.set((UpdateItemRequest) arguments[0]);
                    return null;
                }
                throw new UnsupportedOperationException(method.getName());
            }
        );
        var repository = new AwsDynamoDbTransactionCommandRepositoryAdapter(
            client, "ExpenseTrackerData"
        );

        boolean marked = repository.markEnqueued(new TransactionCommandReference(
            "verified-principal", new TransactionId("client-command-001")
        ));

        assertThat(marked).isTrue();
        assertThat(updated.get().hasExpressionAttributeNames()).isFalse();
        assertThat(updated.get().expressionAttributeValues())
            .containsEntry(":true", AttributeValue.fromBool(true))
            .containsEntry(":false", AttributeValue.fromBool(false));
    }

    @Test
    void omitsUnusedExpressionNamesForCommandEnqueueUpdates() {
        assertThat(AwsDynamoDbTransactionCommandRepositoryAdapter.expressionAttributeNames(
            "SET enqueued = :true",
            "attribute_not_exists(enqueued) OR enqueued = :false"
        )).isEmpty();
    }

    @Test
    void includesStatusExpressionNameForCommandStatusUpdates() {
        assertThat(AwsDynamoDbTransactionCommandRepositoryAdapter.expressionAttributeNames(
            "SET #status = :processing",
            "#status IN (:pending, :processing)"
        )).containsEntry("#status", "status");
    }
}
