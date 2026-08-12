package com.automaticexpense.tracker.domain;

public record DeduplicationResult(
    DeduplicationAction action,
    ReconciliationStatus recommendedStatus,
    TransactionId matchingTransactionId
) {
    public static DeduplicationResult createNew(ReconciliationStatus status) {
        return new DeduplicationResult(DeduplicationAction.CREATE_NEW, status, null);
    }

    public static DeduplicationResult autoMerge(TransactionId matchingTransactionId) {
        return new DeduplicationResult(DeduplicationAction.AUTO_MERGE, ReconciliationStatus.AUTO_MERGED, matchingTransactionId);
    }

    public static DeduplicationResult flagNeedsReview(TransactionId matchingTransactionId) {
        return new DeduplicationResult(DeduplicationAction.FLAG_NEEDS_REVIEW, ReconciliationStatus.NEEDS_REVIEW, matchingTransactionId);
    }
}
