package com.automaticexpense.tracker.domain;

import java.util.Objects;

/**
 * A savings amount deliberately reserved for one goal. Its reference cannot be allocated to another goal.
 */
public record GoalAllocation(String reference, Money amount, String linkedAccountId) {
    public GoalAllocation {
        if (reference == null || reference.isBlank()) {
            throw new IllegalArgumentException("allocation reference cannot be blank");
        }
        Objects.requireNonNull(amount, "allocation amount cannot be null");
        if (amount.amount().signum() <= 0) {
            throw new IllegalArgumentException("allocation amount must be positive");
        }
        if (linkedAccountId != null && linkedAccountId.isBlank()) {
            throw new IllegalArgumentException("linkedAccountId cannot be blank");
        }
    }
}
