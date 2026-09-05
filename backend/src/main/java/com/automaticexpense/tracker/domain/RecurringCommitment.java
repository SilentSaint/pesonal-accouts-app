package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.Objects;
import java.util.Set;

public record RecurringCommitment(
    String id,
    String name,
    RecurringCommitmentClassification classification,
    RecurringCommitmentCadence cadence,
    ExpectedAmountRange expectedAmountRange,
    LocalDate nextPaymentDate,
    double confidence,
    Set<TransactionId> supportingTransactionIds,
    RecurringCommitmentStatus status,
    RecurringCommitmentState state,
    RecurringCommitmentOrigin origin,
    String authoritativeReference,
    String candidateKey
) {
    public RecurringCommitment {
        requireText(id, "id");
        requireText(name, "name");
        Objects.requireNonNull(classification, "classification cannot be null");
        Objects.requireNonNull(cadence, "cadence cannot be null");
        Objects.requireNonNull(expectedAmountRange, "expectedAmountRange cannot be null");
        Objects.requireNonNull(nextPaymentDate, "nextPaymentDate cannot be null");
        if (confidence < 0 || confidence > 1) {
            throw new IllegalArgumentException("confidence must be between zero and one");
        }
        supportingTransactionIds = Set.copyOf(
            Objects.requireNonNull(supportingTransactionIds, "supportingTransactionIds cannot be null")
        );
        Objects.requireNonNull(status, "status cannot be null");
        Objects.requireNonNull(state, "state cannot be null");
        Objects.requireNonNull(origin, "origin cannot be null");
        if (origin == RecurringCommitmentOrigin.DETECTED && (candidateKey == null || candidateKey.isBlank())) {
            throw new IllegalArgumentException("Detected commitment requires a candidate key");
        }
        if (origin != RecurringCommitmentOrigin.DETECTED
            && (authoritativeReference == null || authoritativeReference.isBlank())) {
            throw new IllegalArgumentException("Authoritative commitment requires its reference");
        }
    }

    public RecurringCommitment confirm() {
        if (origin != RecurringCommitmentOrigin.DETECTED || status != RecurringCommitmentStatus.CANDIDATE) {
            throw new IllegalStateException("Only a detected candidate can be confirmed");
        }
        return withStatus(RecurringCommitmentStatus.CONFIRMED);
    }

    public RecurringCommitment ignore() {
        if (origin != RecurringCommitmentOrigin.DETECTED || status != RecurringCommitmentStatus.CANDIDATE) {
            throw new IllegalStateException("Only a detected candidate can be ignored");
        }
        return withStatus(RecurringCommitmentStatus.IGNORED);
    }

    public RecurringCommitment cancel() {
        if (origin != RecurringCommitmentOrigin.DETECTED || status != RecurringCommitmentStatus.CONFIRMED) {
            throw new IllegalStateException("Only a confirmed commitment can be cancelled");
        }
        return withStatus(RecurringCommitmentStatus.CANCELLED);
    }

    public RecurringCommitment restore() {
        if (origin != RecurringCommitmentOrigin.DETECTED
            || (status != RecurringCommitmentStatus.IGNORED && status != RecurringCommitmentStatus.CANCELLED)) {
            throw new IllegalStateException("Only an ignored or cancelled commitment can be restored");
        }
        return withStatus(status == RecurringCommitmentStatus.IGNORED
            ? RecurringCommitmentStatus.CANDIDATE
            : RecurringCommitmentStatus.CONFIRMED);
    }

    public RecurringCommitment corrected(
        String updatedName,
        RecurringCommitmentClassification updatedClassification,
        RecurringCommitmentCadence updatedCadence,
        ExpectedAmountRange updatedRange,
        LocalDate updatedNextPaymentDate
    ) {
        if (origin != RecurringCommitmentOrigin.DETECTED || status != RecurringCommitmentStatus.CONFIRMED) {
            throw new IllegalStateException("Only a confirmed commitment can be corrected");
        }
        return new RecurringCommitment(
            id, updatedName, updatedClassification, updatedCadence, updatedRange, updatedNextPaymentDate,
            confidence, supportingTransactionIds, status,
            stateFor(updatedRange, updatedCadence, updatedNextPaymentDate, updatedNextPaymentDate),
            origin, authoritativeReference, candidateKey
        );
    }

    public RecurringCommitment asOf(LocalDate asOf) {
        return new RecurringCommitment(
            id, name, classification, cadence, expectedAmountRange, nextPaymentDate, confidence,
            supportingTransactionIds, status, stateFor(expectedAmountRange, cadence, nextPaymentDate, asOf),
            origin, authoritativeReference, candidateKey
        );
    }

    private RecurringCommitment withStatus(RecurringCommitmentStatus updatedStatus) {
        return new RecurringCommitment(
            id, name, classification, cadence, expectedAmountRange, nextPaymentDate, confidence,
            supportingTransactionIds, updatedStatus, state, origin, authoritativeReference, candidateKey
        );
    }

    public static RecurringCommitment authoritative(
        String id,
        String name,
        RecurringCommitmentClassification classification,
        RecurringCommitmentCadence cadence,
        ExpectedAmountRange range,
        LocalDate nextPaymentDate,
        RecurringCommitmentOrigin origin,
        String authoritativeReference
    ) {
        if (origin == RecurringCommitmentOrigin.DETECTED) {
            throw new IllegalArgumentException("Authoritative commitment must have an authoritative origin");
        }
        return new RecurringCommitment(
            id, name, classification, cadence, range, nextPaymentDate, 1.0, Set.of(),
            RecurringCommitmentStatus.CONFIRMED,
            range.isVariable() ? RecurringCommitmentState.VARIABLE_AMOUNT : RecurringCommitmentState.ON_TRACK,
            origin, authoritativeReference, null
        );
    }

    private static RecurringCommitmentState stateFor(
        ExpectedAmountRange range, RecurringCommitmentCadence cadence, LocalDate expectedDate, LocalDate asOf
    ) {
        if (asOf.isAfter(expectedDate.plusDays(cadence.lateToleranceDays()))) {
            return RecurringCommitmentState.MISSED;
        }
        if (asOf.isAfter(expectedDate)) {
            return RecurringCommitmentState.LATE;
        }
        return range.isVariable() ? RecurringCommitmentState.VARIABLE_AMOUNT : RecurringCommitmentState.ON_TRACK;
    }

    private static void requireText(String value, String field) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(field + " cannot be blank");
        }
    }
}
