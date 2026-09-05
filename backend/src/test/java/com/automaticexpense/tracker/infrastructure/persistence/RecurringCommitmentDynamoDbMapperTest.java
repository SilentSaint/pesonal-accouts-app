package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.ExpectedAmountRange;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.RecurringCommitment;
import com.automaticexpense.tracker.domain.RecurringCommitmentCadence;
import com.automaticexpense.tracker.domain.RecurringCommitmentClassification;
import com.automaticexpense.tracker.domain.RecurringCommitmentOrigin;
import com.automaticexpense.tracker.domain.RecurringCommitmentState;
import com.automaticexpense.tracker.domain.RecurringCommitmentStatus;
import com.automaticexpense.tracker.domain.TransactionId;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class RecurringCommitmentDynamoDbMapperTest {

    @Test
    void mapsAConfirmedCommitmentToTheUserScopedRecurringKeyWithoutLosingEvidenceOrDecision() {
        RecurringCommitment commitment = new RecurringCommitment(
            "streamflix", "StreamFlix", RecurringCommitmentClassification.SUBSCRIPTION,
            RecurringCommitmentCadence.MONTHLY,
            new ExpectedAmountRange(Money.of("499.00", "INR"), Money.of("499.00", "INR")),
            LocalDate.of(2026, 4, 5), 0.95, Set.of(new TransactionId("feb"), new TransactionId("mar")),
            RecurringCommitmentStatus.CONFIRMED, RecurringCommitmentState.ON_TRACK,
            RecurringCommitmentOrigin.DETECTED, null, "streamflix|card|INR|MONTHLY"
        );

        Map<String, String> item = RecurringCommitmentDynamoDbMapper.from("principal-42", commitment);

        assertThat(item).containsEntry("PK", "USER#principal-42")
            .containsEntry("SK", "RECUR#streamflix")
            .containsEntry("entityType", "RECURRING_COMMITMENT");
        assertThat(RecurringCommitmentDynamoDbMapper.to(item)).isEqualTo(commitment);
    }
}
