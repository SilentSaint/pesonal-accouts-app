package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class RecurringCommitmentTest {

    @Test
    void requiresAUserDecisionBeforeADetectedCandidateBecomesAConfirmedObligation() {
        RecurringCommitment candidate = candidate();

        assertThat(candidate.status()).isEqualTo(RecurringCommitmentStatus.CANDIDATE);
        assertThat(candidate.confirm().status()).isEqualTo(RecurringCommitmentStatus.CONFIRMED);
        assertThatThrownBy(() -> candidate.cancel())
            .hasMessage("Only a confirmed commitment can be cancelled");
    }

    @Test
    void explainsLateAndMissedExpectedOccurrencesWithoutChangingTheCommitmentStatus() {
        RecurringCommitment confirmed = candidate().confirm();

        assertThat(confirmed.asOf(LocalDate.of(2026, 4, 8)).state())
            .isEqualTo(RecurringCommitmentState.LATE);
        assertThat(confirmed.asOf(LocalDate.of(2026, 4, 13)).state())
            .isEqualTo(RecurringCommitmentState.MISSED);
        assertThat(confirmed.status()).isEqualTo(RecurringCommitmentStatus.CONFIRMED);
    }

    private RecurringCommitment candidate() {
        return new RecurringCommitment(
            "streamflix", "StreamFlix", RecurringCommitmentClassification.SUBSCRIPTION,
            RecurringCommitmentCadence.MONTHLY,
            new ExpectedAmountRange(Money.of("499.00", "INR"), Money.of("499.00", "INR")),
            LocalDate.of(2026, 4, 5), 0.95, Set.of(new TransactionId("mar-debit")),
            RecurringCommitmentStatus.CANDIDATE, RecurringCommitmentState.ON_TRACK,
            RecurringCommitmentOrigin.DETECTED, null, "streamflix|card|INR|MONTHLY"
        );
    }
}
