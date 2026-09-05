package com.automaticexpense.tracker.domain;

import java.util.Objects;

public record FormulaReference(String id, String version) {
    public FormulaReference {
        if (id == null || id.isBlank()) {
            throw new IllegalArgumentException("formula id cannot be blank");
        }
        if (version == null || version.isBlank()) {
            throw new IllegalArgumentException("formula version cannot be blank");
        }
    }
}
