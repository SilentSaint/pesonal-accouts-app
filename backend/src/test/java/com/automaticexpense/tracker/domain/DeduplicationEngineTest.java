package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class DeduplicationEngineTest {

    private final DeduplicationEngine engine = new DeduplicationEngine();

    @Test
    void shouldReturnNewTransactionWhenNoExistingTransactionsInWindow() {
        ParsedTransactionEvent candidate = new ParsedTransactionEvent(
            new BigDecimal("500.00"),
            "INR",
            TransactionType.DEBIT,
            "1234",
            "Starbucks",
            LocalDateTime.of(2026, 7, 26, 12, 0)
        );

        DeduplicationResult result = engine.evaluate(candidate, IngestionSource.EMAIL, Collections.emptyList());

        assertThat(result.action()).isEqualTo(DeduplicationAction.CREATE_NEW);
        assertThat(result.recommendedStatus()).isEqualTo(ReconciliationStatus.CONFIRMED);
    }

    @Test
    void shouldAutoMergeWhenExactAmountAndMerchantMatchWithin15Minutes() {
        LocalDateTime baseTime = LocalDateTime.of(2026, 7, 26, 12, 0);

        Transaction existingSmsTxn = new Transaction(
            new TransactionId("txn-sms-1"),
            new Money(new BigDecimal("500.00"), "INR"),
            TransactionType.DEBIT,
            baseTime,
            "Starbucks",
            new AccountId("acc-1"),
            null,
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            new Money(new BigDecimal("500.00"), "INR")
        );

        ParsedTransactionEvent candidateEmail = new ParsedTransactionEvent(
            new BigDecimal("500.00"),
            "INR",
            TransactionType.DEBIT,
            "1234",
            "Starbucks",
            baseTime.plusMinutes(8) // Within +15m window
        );

        DeduplicationResult result = engine.evaluate(candidateEmail, IngestionSource.EMAIL, List.of(existingSmsTxn));

        assertThat(result.action()).isEqualTo(DeduplicationAction.AUTO_MERGE);
        assertThat(result.matchingTransactionId()).isEqualTo(existingSmsTxn.id());
    }

    @Test
    void shouldFlagNeedsReviewWhenAmountMatchesWithin15MinutesButMerchantIsAmbiguous() {
        LocalDateTime baseTime = LocalDateTime.of(2026, 7, 26, 12, 0);

        Transaction existingSmsTxn = new Transaction(
            new TransactionId("txn-sms-2"),
            new Money(new BigDecimal("350.00"), "INR"),
            TransactionType.DEBIT,
            baseTime,
            "Bundl Tech",
            new AccountId("acc-1"),
            null,
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            new Money(new BigDecimal("350.00"), "INR")
        );

        ParsedTransactionEvent candidateEmail = new ParsedTransactionEvent(
            new BigDecimal("350.00"),
            "INR",
            TransactionType.DEBIT,
            "1234",
            "Swiggy Pay", // Ambiguous / different merchant string
            baseTime.plusMinutes(12) // Within 15m window
        );

        DeduplicationResult result = engine.evaluate(candidateEmail, IngestionSource.EMAIL, List.of(existingSmsTxn));

        assertThat(result.action()).isEqualTo(DeduplicationAction.FLAG_NEEDS_REVIEW);
        assertThat(result.recommendedStatus()).isEqualTo(ReconciliationStatus.NEEDS_REVIEW);
    }
}
