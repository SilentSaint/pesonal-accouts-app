package com.automaticexpense.tracker.domain;

/**
 * A reviewable transaction and, when applicable, the canonical transaction it may duplicate.
 */
public record ReconciliationReview(Transaction candidate, Transaction canonical) {
}
