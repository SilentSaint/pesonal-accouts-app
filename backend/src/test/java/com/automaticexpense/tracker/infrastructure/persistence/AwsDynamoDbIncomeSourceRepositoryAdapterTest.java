package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IncomeCadence;
import com.automaticexpense.tracker.domain.IncomeSource;
import com.automaticexpense.tracker.domain.IncomeSourceType;
import com.automaticexpense.tracker.domain.Money;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;

import java.lang.reflect.Proxy;
import java.time.LocalDate;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Queue;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class AwsDynamoDbIncomeSourceRepositoryAdapterTest {

    @Test
    void replacesASuggestionOnlyWhenItsPersistedStatusIsStillPending() {
        List<PutItemRequest> requests = new ArrayList<>();
        DynamoDbClient client = (DynamoDbClient) Proxy.newProxyInstance(
            getClass().getClassLoader(),
            new Class<?>[] {DynamoDbClient.class},
            (proxy, method, arguments) -> {
                if (method.getName().equals("putItem")) {
                    requests.add((PutItemRequest) arguments[0]);
                    return null;
                }
                throw new UnsupportedOperationException(method.getName());
            }
        );
        IncomeSource confirmed = income("income-1", "75000.00");

        boolean replaced = new AwsDynamoDbIncomeSourceRepositoryAdapter(
            client, "ExpenseTrackerData", "verified-principal"
        ).replaceIfPending(confirmed);

        assertThat(replaced).isTrue();
        assertThat(requests).singleElement().satisfies(request -> {
            assertThat(request.conditionExpression()).isEqualTo("#status = :pending");
            assertThat(request.expressionAttributeNames()).containsEntry("#status", "confirmationStatus");
            assertThat(request.expressionAttributeValues())
                .containsEntry(":pending", AttributeValue.fromS("PENDING"));
        });
    }

    @Test
    void doesNotReportARefreshAsSuccessfulWhenAConcurrentDecisionChangedTheSuggestion() {
        DynamoDbClient client = (DynamoDbClient) Proxy.newProxyInstance(
            getClass().getClassLoader(),
            new Class<?>[] {DynamoDbClient.class},
            (proxy, method, arguments) -> {
                if (method.getName().equals("putItem")) {
                    throw ConditionalCheckFailedException.builder().build();
                }
                throw new UnsupportedOperationException(method.getName());
            }
        );

        boolean replaced = new AwsDynamoDbIncomeSourceRepositoryAdapter(
            client, "ExpenseTrackerData", "verified-principal"
        ).replaceIfPending(income("income-1", "75000.00"));

        assertThat(replaced).isFalse();
    }

    @Test
    void findsEveryIncomeSourcePageByPassingLastEvaluatedKeyToTheNextQuery() {
        IncomeSource first = income("income-first", "75000.00");
        IncomeSource second = income("income-second", "12000.00");
        Map<String, AttributeValue> lastKey = Map.of(
            "PK", AttributeValue.fromS("USER#verified-principal"),
            "SK", AttributeValue.fromS("INCOME#income-first")
        );
        Queue<QueryResponse> responses = new ArrayDeque<>(List.of(
            QueryResponse.builder().items(item(first)).lastEvaluatedKey(lastKey).build(),
            QueryResponse.builder().items(item(second)).build()
        ));
        List<QueryRequest> requests = new ArrayList<>();
        DynamoDbClient client = (DynamoDbClient) Proxy.newProxyInstance(
            getClass().getClassLoader(),
            new Class<?>[] {DynamoDbClient.class},
            (proxy, method, arguments) -> {
                if (method.getName().equals("query")) {
                    requests.add((QueryRequest) arguments[0]);
                    return responses.remove();
                }
                throw new UnsupportedOperationException(method.getName());
            }
        );

        List<IncomeSource> sources =
            new AwsDynamoDbIncomeSourceRepositoryAdapter(client, "ExpenseTrackerData", "verified-principal")
                .findAll();

        assertThat(sources).containsExactly(first, second);
        assertThat(requests).hasSize(2);
        assertThat(requests.get(1).exclusiveStartKey()).isEqualTo(lastKey);
    }

    private IncomeSource income(String id, String amount) {
        return IncomeSource.confirmed(
            id, "Income " + id, IncomeSourceType.FIXED, Money.of(amount, "INR"),
            IncomeCadence.MONTHLY, LocalDate.of(2026, 1, 1), null,
            new AccountId("income-account"), Set.of()
        );
    }

    private Map<String, AttributeValue> item(IncomeSource income) {
        Map<String, AttributeValue> result = new HashMap<>();
        DynamoDbItem.fromIncomeSource("verified-principal", income)
            .forEach((name, value) -> result.put(name, AttributeValue.fromS(value)));
        return result;
    }
}
