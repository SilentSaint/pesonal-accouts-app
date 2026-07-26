package com.automaticexpense.tracker.domain;

import java.util.Objects;

public record AccountId(String value) {
    public AccountId {
        Objects.requireNonNull(value, "AccountId value cannot be null");
        if (value.isBlank()) {
            throw new IllegalArgumentException("AccountId value cannot be blank");
        }
    }
}
