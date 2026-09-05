package com.automaticexpense.tracker.infrastructure.api;

import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;
import software.amazon.awssdk.services.sqs.model.SendMessageResponse;

import java.lang.reflect.Proxy;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class DailyProactiveInsightSchedulerTest {

    @Test
    void queuesOneBoundedRefreshForEachObservedInsightOwner() {
        DynamoDbClient dynamo = (DynamoDbClient) Proxy.newProxyInstance(
            getClass().getClassLoader(), new Class<?>[]{DynamoDbClient.class}, (proxy, method, arguments) -> {
                if ("query".equals(method.getName())) {
                    return QueryResponse.builder().items(List.of(
                        Map.of("userId", AttributeValue.fromS("scope-a")),
                        Map.of("userId", AttributeValue.fromS("scope-b"))
                    )).build();
                }
                if ("serviceName".equals(method.getName())) return "DynamoDb";
                throw new UnsupportedOperationException(method.getName());
            }
        );
        List<SendMessageRequest> messages = new ArrayList<>();
        SqsClient queue = (SqsClient) Proxy.newProxyInstance(
            getClass().getClassLoader(), new Class<?>[]{SqsClient.class}, (proxy, method, arguments) -> {
                if ("sendMessage".equals(method.getName())) {
                    messages.add((SendMessageRequest) arguments[0]);
                    return SendMessageResponse.builder().build();
                }
                if ("serviceName".equals(method.getName())) return "Sqs";
                throw new UnsupportedOperationException(method.getName());
            }
        );
        DailyProactiveInsightScheduler scheduler = new DailyProactiveInsightScheduler(
            dynamo, queue, "ExpenseTrackerData", "https://queue.example/insights",
            () -> Instant.parse("2026-08-31T12:00:00Z")
        );

        scheduler.handleRequest(null, null);

        assertThat(messages).extracting(SendMessageRequest::messageBody)
            .anySatisfy(body -> assertThat(body).contains(
                "\"userId\":\"scope-a\"", "\"asOf\":\"2026-08-31T12:00:00Z\""
            ))
            .anySatisfy(body -> assertThat(body).contains("\"userId\":\"scope-b\""));
    }
}
