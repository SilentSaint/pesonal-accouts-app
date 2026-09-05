package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.FinancialGoal;
import com.automaticexpense.tracker.domain.GoalAllocation;
import com.automaticexpense.tracker.domain.GoalContribution;
import com.automaticexpense.tracker.domain.GoalContributionRule;
import com.automaticexpense.tracker.domain.GoalPriority;
import com.automaticexpense.tracker.domain.Money;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.TransactWriteItemsRequest;

import java.lang.reflect.Proxy;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

class AwsDynamoDbFinancialGoalRepositoryAdapterTest {

    @Test
    void persistsAndRestoresAPrincipalScopedGoalWithContributionEvidence() {
        AtomicReference<TransactWriteItemsRequest> saved = new AtomicReference<>();
        DynamoDbClient client = (DynamoDbClient) Proxy.newProxyInstance(
            getClass().getClassLoader(), new Class<?>[] {DynamoDbClient.class},
            (proxy, method, arguments) -> {
                if (method.getName().equals("transactWriteItems")) {
                    saved.set((TransactWriteItemsRequest) arguments[0]);
                    return null;
                }
                if (method.getName().equals("getItem")) {
                    if (saved.get() == null) {
                        return software.amazon.awssdk.services.dynamodb.model.GetItemResponse.builder().build();
                    }
                    return software.amazon.awssdk.services.dynamodb.model.GetItemResponse.builder()
                        .item(saved.get().transactItems().getFirst().put().item()).build();
                }
                throw new UnsupportedOperationException(method.getName());
            }
        );
        FinancialGoal goal = FinancialGoal.active(
            "goal-1", "Home deposit", Money.of("100000.00", "INR"), LocalDate.of(2027, 12, 31),
            List.of(new GoalAllocation("reserved;savings", Money.of("25000.00", "INR"), "savings,account")),
            GoalPriority.HIGH, GoalContributionRule.none()
        ).recordContribution(new GoalContribution(
            "contribution-1", Money.of("5000.00", "INR"), LocalDate.of(2026, 3, 1), "transaction-1"
        ));
        AwsDynamoDbFinancialGoalRepositoryAdapter repository =
            new AwsDynamoDbFinancialGoalRepositoryAdapter(client, "ExpenseTrackerData", "verified-principal");

        repository.save(goal);
        FinancialGoal restored = repository.findById(goal.id()).orElseThrow();

        assertThat(saved.get().transactItems().getFirst().put().item())
            .containsEntry("PK", AttributeValue.fromS("USER#verified-principal"))
            .containsEntry("SK", AttributeValue.fromS("GOAL#goal-1"));
        assertThat(saved.get().transactItems().get(1).put().conditionExpression())
            .isEqualTo("attribute_not_exists(PK) OR #goalId = :goalId");
        assertThat(restored).isEqualTo(goal);
    }
}
