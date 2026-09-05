package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.Objects;
import java.util.Set;

/**
 * A user-confirmed or proposed source of income. Transaction evidence is retained for explanation,
 * but confirmation never changes the transaction itself.
 */
public record IncomeSource(
    String id,
    String name,
    IncomeSourceType type,
    Money amount,
    IncomeCadence cadence,
    LocalDate effectiveFrom,
    LocalDate effectiveTo,
    AccountId linkedAccountId,
    IncomeConfirmationStatus confirmationStatus,
    Set<TransactionId> sourceTransactionIds,
    String suggestionKey
) {
    public IncomeSource {
        if (id == null || id.isBlank()) {
            throw new IllegalArgumentException("id cannot be blank");
        }
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("name cannot be blank");
        }
        Objects.requireNonNull(type, "type cannot be null");
        Objects.requireNonNull(amount, "amount cannot be null");
        if (amount.amount().signum() <= 0) {
            throw new IllegalArgumentException("amount must be positive");
        }
        Objects.requireNonNull(cadence, "cadence cannot be null");
        Objects.requireNonNull(effectiveFrom, "effectiveFrom cannot be null");
        if (effectiveTo != null && effectiveTo.isBefore(effectiveFrom)) {
            throw new IllegalArgumentException("effectiveTo cannot be before effectiveFrom");
        }
        Objects.requireNonNull(linkedAccountId, "linkedAccountId cannot be null");
        Objects.requireNonNull(confirmationStatus, "confirmationStatus cannot be null");
        sourceTransactionIds = Set.copyOf(Objects.requireNonNull(sourceTransactionIds,
            "sourceTransactionIds cannot be null"));
        if (type == IncomeSourceType.ONE_TIME && cadence != IncomeCadence.ONCE) {
            throw new IllegalArgumentException("one-time income must use ONCE cadence");
        }
        if (type != IncomeSourceType.ONE_TIME && cadence == IncomeCadence.ONCE) {
            throw new IllegalArgumentException("only one-time income may use ONCE cadence");
        }
    }

    public static IncomeSource confirmed(
        String id,
        String name,
        IncomeSourceType type,
        Money amount,
        IncomeCadence cadence,
        LocalDate effectiveFrom,
        LocalDate effectiveTo,
        AccountId linkedAccountId,
        Set<TransactionId> sourceTransactionIds
    ) {
        return new IncomeSource(
            id, name, type, amount, cadence, effectiveFrom, effectiveTo, linkedAccountId,
            IncomeConfirmationStatus.CONFIRMED, sourceTransactionIds, null
        );
    }

    public static IncomeSource suggested(
        String id,
        String name,
        IncomeSourceType type,
        Money amount,
        IncomeCadence cadence,
        LocalDate effectiveFrom,
        LocalDate effectiveTo,
        AccountId linkedAccountId,
        Set<TransactionId> sourceTransactionIds,
        String suggestionKey
    ) {
        if (suggestionKey == null || suggestionKey.isBlank()) {
            throw new IllegalArgumentException("suggestionKey cannot be blank");
        }
        return new IncomeSource(
            id, name, type, amount, cadence, effectiveFrom, effectiveTo, linkedAccountId,
            IncomeConfirmationStatus.PENDING, sourceTransactionIds, suggestionKey
        );
    }

    public IncomeSource confirm() {
        return confirmationStatus == IncomeConfirmationStatus.PENDING
            ? withConfirmationStatus(IncomeConfirmationStatus.CONFIRMED)
            : this;
    }

    public IncomeSource reject() {
        return confirmationStatus == IncomeConfirmationStatus.PENDING
            ? withConfirmationStatus(IncomeConfirmationStatus.REJECTED)
            : this;
    }

    public IncomeSource withEffectiveDates(LocalDate newEffectiveFrom, LocalDate newEffectiveTo) {
        return new IncomeSource(
            id, name, type, amount, cadence, newEffectiveFrom, newEffectiveTo, linkedAccountId,
            confirmationStatus, sourceTransactionIds, suggestionKey
        );
    }

    public boolean isActiveOn(LocalDate date) {
        Objects.requireNonNull(date, "date cannot be null");
        return !date.isBefore(effectiveFrom) && (effectiveTo == null || !date.isAfter(effectiveTo));
    }

    public boolean isConfirmed() {
        return confirmationStatus == IncomeConfirmationStatus.CONFIRMED;
    }

    private IncomeSource withConfirmationStatus(IncomeConfirmationStatus status) {
        return new IncomeSource(
            id, name, type, amount, cadence, effectiveFrom, effectiveTo, linkedAccountId,
            status, sourceTransactionIds, suggestionKey
        );
    }
}
