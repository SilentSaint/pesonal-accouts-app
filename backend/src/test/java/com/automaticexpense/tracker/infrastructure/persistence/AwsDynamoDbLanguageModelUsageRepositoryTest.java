package com.automaticexpense.tracker.infrastructure.persistence;

import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.UpdateItemRequest;

import java.lang.reflect.Proxy;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class AwsDynamoDbLanguageModelUsageRepositoryTest {

    @Test
    void reservesACallUsingAnAtomicMonthScopedConditionalWrite() {
        List<UpdateItemRequest> requests = new ArrayList<>();
        DynamoDbClient client = client(requests, false);

        boolean reserved = new AwsDynamoDbLanguageModelUsageRepository(client, "ExpenseTrackerData")
            .reserve("GEMINI", YearMonth.of(2026, 8), 50);

        assertThat(reserved).isTrue();
        assertThat(requests).singleElement().satisfies(request -> {
            assertThat(request.key()).containsEntry("PK", AttributeValue.fromS("SYSTEM#LANGUAGE_MODEL"));
            assertThat(request.key()).containsEntry("SK", AttributeValue.fromS("LLM_USAGE#GEMINI#2026-08"));
            assertThat(request.conditionExpression()).contains("#calls < :maximum");
            assertThat(request.expressionAttributeValues())
                .containsEntry(":maximum", AttributeValue.fromN("50"));
        });
    }

    @Test
    void opensTheCircuitWhenTheConditionalReservationFails() {
        boolean reserved = new AwsDynamoDbLanguageModelUsageRepository(client(new ArrayList<>(), true),
            "ExpenseTrackerData").reserve("GEMINI", YearMonth.of(2026, 8), 50);

        assertThat(reserved).isFalse();
    }

    private DynamoDbClient client(List<UpdateItemRequest> requests, boolean exhausted) {
        return (DynamoDbClient) Proxy.newProxyInstance(
            getClass().getClassLoader(),
            new Class<?>[] {DynamoDbClient.class},
            (proxy, method, arguments) -> {
                if ("updateItem".equals(method.getName())) {
                    requests.add((UpdateItemRequest) arguments[0]);
                    if (exhausted) {
                        throw ConditionalCheckFailedException.builder().build();
                    }
                    return null;
                }
                if ("serviceName".equals(method.getName())) {
                    return "DynamoDb";
                }
                if ("close".equals(method.getName())) {
                    return null;
                }
                throw new UnsupportedOperationException(method.getName());
            }
        );
    }
}
