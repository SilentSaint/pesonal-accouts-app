package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.ExpectedAmountRange;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.RecurringCommitment;
import com.automaticexpense.tracker.domain.RecurringCommitmentCadence;
import com.automaticexpense.tracker.domain.RecurringCommitmentClassification;
import com.automaticexpense.tracker.domain.RecurringCommitmentOrigin;
import com.automaticexpense.tracker.domain.RecurringCommitmentState;
import com.automaticexpense.tracker.domain.RecurringCommitmentStatus;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;

import java.lang.reflect.Proxy;
import java.time.LocalDate;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

class AwsDynamoDbRecurringCommitmentRepositoryAdapterTest {

    @Test
    void savesTheDecisionUnderTheVerifiedPrincipalsRecurringKey() {
        AtomicReference<PutItemRequest> written = new AtomicReference<>();
        DynamoDbClient client = (DynamoDbClient) Proxy.newProxyInstance(
            getClass().getClassLoader(), new Class<?>[] {DynamoDbClient.class},
            (proxy, method, arguments) -> {
                if (method.getName().equals("putItem")) {
                    written.set((PutItemRequest) arguments[0]);
                    return null;
                }
                throw new UnsupportedOperationException(method.getName());
            }
        );
        RecurringCommitment commitment = new RecurringCommitment(
            "rent-1", "Home rent", RecurringCommitmentClassification.RENT,
            RecurringCommitmentCadence.MONTHLY,
            new ExpectedAmountRange(Money.of("25000.00", "INR"), Money.of("25000.00", "INR")),
            LocalDate.of(2026, 4, 1), 1.0, java.util.Set.of(), RecurringCommitmentStatus.CONFIRMED,
            RecurringCommitmentState.ON_TRACK, RecurringCommitmentOrigin.DETECTED, null, "manual:rent-1"
        );

        new AwsDynamoDbRecurringCommitmentRepositoryAdapter(client, "ExpenseTrackerData", "verified-user")
            .save(commitment);

        assertThat(written.get().item()).containsEntry("PK", software.amazon.awssdk.services.dynamodb.model.AttributeValue.fromS("USER#verified-user"))
            .containsEntry("SK", software.amazon.awssdk.services.dynamodb.model.AttributeValue.fromS("RECUR#rent-1"));
    }
}
