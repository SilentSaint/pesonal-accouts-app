package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.TransactWriteItemsRequest;
import software.amazon.awssdk.services.dynamodb.model.TransactWriteItemsResponse;

import java.lang.reflect.Proxy;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class AwsDynamoDbProactiveInsightRepositoryAdapterTest {

    @Test
    void atomicallyPersistsTheInsightAndItsDeduplicationMarkerInTheOwnersPartition() {
        CapturedRequest captured = new CapturedRequest();
        DynamoDbClient client = (DynamoDbClient) Proxy.newProxyInstance(
            getClass().getClassLoader(), new Class<?>[]{DynamoDbClient.class}, (proxy, method, arguments) -> {
                if ("transactWriteItems".equals(method.getName())) {
                    captured.request = (TransactWriteItemsRequest) arguments[0];
                    return TransactWriteItemsResponse.builder().build();
                }
                if ("serviceName".equals(method.getName())) return "DynamoDb";
                throw new UnsupportedOperationException(method.getName());
            }
        );
        AwsDynamoDbProactiveInsightRepositoryAdapter adapter =
            new AwsDynamoDbProactiveInsightRepositoryAdapter(client, "ExpenseTrackerData");

        boolean inserted = adapter.saveIfAbsent("scope-a", insight());

        assertThat(inserted).isTrue();
        assertThat(captured.request.transactItems()).hasSize(2);
        assertThat(captured.request.transactItems().get(0).put().item())
            .containsEntry("PK", software.amazon.awssdk.services.dynamodb.model.AttributeValue.fromS("USER#scope-a"));
        assertThat(captured.request.transactItems().get(0).put().item().get("SK").s())
            .startsWith("INSIGHT#2026-08-31T18:30:00Z#insight-1");
        assertThat(captured.request.transactItems().get(1).put().item().get("SK").s())
            .isEqualTo("INSIGHT_DEDUP#CATEGORY_INCREASE:GROCERIES:2026-08");
        assertThat(captured.request.transactItems())
            .allSatisfy(item -> assertThat(item.put().conditionExpression())
                .isEqualTo("attribute_not_exists(PK) AND attribute_not_exists(SK)"));
    }

    private ProactiveInsight insight() {
        Money amount = Money.of("5000.00", "INR");
        return new ProactiveInsight(
            "insight-1", ProactiveInsightType.CATEGORY_INCREASE, IntelligenceClassification.DERIVED_INSIGHT,
            "Category spending increased", "GROCERIES is higher than usual.", amount, Money.of("2000.00", "INR"),
            "three comparable prior months", new java.math.BigDecimal("0.90"),
            Instant.parse("2026-08-31T18:30:00Z"), Instant.parse("2026-08-31T18:30:00Z"),
            ProactiveInsightCalculator.FORMULA,
            new EvidenceMetadata(1, new DrillDownReference(
                new DateRange(java.time.LocalDate.of(2026, 8, 1), java.time.LocalDate.of(2026, 8, 31)),
                "INR", java.util.Set.of(), "GROCERIES", null
            )),
            List.of(new TransactionEvidence("txn-1", LocalDateTime.parse("2026-08-12T10:00"), "Grocer", amount)),
            List.of("canonical"), List.of(), "CATEGORY_INCREASE:GROCERIES:2026-08",
            Instant.parse("2026-08-31T18:30:00Z"), Instant.parse("2026-10-01T18:30:00Z"),
            InsightLifecycleState.ACTIVE
        );
    }

    private static final class CapturedRequest {
        private TransactWriteItemsRequest request;
    }
}
