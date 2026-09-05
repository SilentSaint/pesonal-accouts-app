package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.DynamodbEvent;
import com.amazonaws.services.lambda.runtime.events.models.dynamodb.AttributeValue;
import com.amazonaws.services.lambda.runtime.events.models.dynamodb.StreamRecord;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;
import software.amazon.awssdk.services.sqs.model.SendMessageResponse;

import java.lang.reflect.Proxy;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class CanonicalTransactionInsightEnqueuerTest {

    @Test
    void enqueuesOnlyCanonicalTransactionChangesAndRejectsDerivedInsightRecords() {
        List<SendMessageRequest> requests = new ArrayList<>();
        SqsClient queue = (SqsClient) Proxy.newProxyInstance(
            getClass().getClassLoader(), new Class<?>[]{SqsClient.class}, (proxy, method, arguments) -> {
                if ("sendMessage".equals(method.getName())) {
                    requests.add((SendMessageRequest) arguments[0]);
                    return SendMessageResponse.builder().build();
                }
                if ("serviceName".equals(method.getName())) return "Sqs";
                throw new UnsupportedOperationException(method.getName());
            }
        );
        CanonicalTransactionInsightEnqueuer handler = new CanonicalTransactionInsightEnqueuer(
            queue, "https://queue.example/insights", () -> Instant.parse("2026-08-31T12:00:00Z")
        );
        DynamodbEvent event = new DynamodbEvent();
        event.setRecords(List.of(
            record("INSERT", "USER#scope-a", "TXN#2026-08-31#transaction-1", "TRANSACTION"),
            record("INSERT", "USER#scope-a", "INSIGHT#2026-08-31#insight-1", "PROACTIVE_INSIGHT")
        ));

        handler.handleRequest(event, null);

        assertThat(requests).singleElement().satisfies(request -> {
            assertThat(request.queueUrl()).isEqualTo("https://queue.example/insights");
            assertThat(request.messageBody()).contains(
                "\"userId\":\"scope-a\"",
                "\"currency\":\"INR\"",
                "\"asOf\":\"2026-08-31T12:00:00Z\""
            );
            assertThat(request.messageBody()).doesNotContain("TXN#", "INSIGHT#");
        });
    }

    private DynamodbEvent.DynamodbStreamRecord record(
        String operation, String partition, String sort, String entityType
    ) {
        StreamRecord image = new StreamRecord();
        image.setNewImage(Map.of(
            "PK", new AttributeValue().withS(partition),
            "SK", new AttributeValue().withS(sort),
            "entityType", new AttributeValue().withS(entityType),
            "currency", new AttributeValue().withS("INR")
        ));
        DynamodbEvent.DynamodbStreamRecord record = new DynamodbEvent.DynamodbStreamRecord();
        record.setEventName(operation);
        record.setEventID("event-1");
        record.setDynamodb(image);
        return record;
    }
}
