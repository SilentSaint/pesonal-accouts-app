package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.ContextProvenance;
import com.automaticexpense.tracker.domain.FinancialContextCapability;
import com.automaticexpense.tracker.domain.FinancialContextItem;
import com.automaticexpense.tracker.domain.FinancialContextType;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;

import java.lang.reflect.Proxy;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Queue;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class AwsDynamoDbFinancialContextRepositoryAdapterTest {

    @Test
    void findsEveryContextPageByPassingLastEvaluatedKeyToTheNextQuery() {
        FinancialContextItem first = cashFloor("ctx-first", "10000.00");
        FinancialContextItem second = cashFloor("ctx-second", "25000.00");
        Map<String, AttributeValue> lastKey = Map.of(
            "PK", AttributeValue.fromS("USER#verified-principal"),
            "SK", AttributeValue.fromS("CONTEXT#ctx-first")
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

        List<FinancialContextItem> contexts =
            new AwsDynamoDbFinancialContextRepositoryAdapter(client, "ExpenseTrackerData", "verified-principal")
                .findAll();

        assertThat(contexts).containsExactly(first, second);
        assertThat(requests).hasSize(2);
        assertThat(requests.get(1).exclusiveStartKey()).isEqualTo(lastKey);
    }

    private FinancialContextItem cashFloor(String id, String amount) {
        return FinancialContextItem.create(
            id,
            FinancialContextType.PREFERRED_MINIMUM_CASH_BALANCE,
            "Cash floor",
            Map.of("amount", amount, "currency", "INR"),
            Set.of(FinancialContextCapability.CASH_FLOW_FORECAST),
            ContextProvenance.USER_DECLARED,
            null,
            null,
            Instant.parse("2026-08-29T10:00:00Z")
        );
    }

    private Map<String, AttributeValue> item(FinancialContextItem context) {
        Map<String, AttributeValue> result = new HashMap<>();
        DynamoDbItem.fromFinancialContextItem("verified-principal", context)
            .forEach((name, value) -> result.put(name, AttributeValue.fromS(value)));
        return result;
    }
}
