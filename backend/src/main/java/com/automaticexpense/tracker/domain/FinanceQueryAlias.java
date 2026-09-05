package com.automaticexpense.tracker.domain;

import java.util.List;
import java.util.Locale;
import java.util.Objects;

public record FinanceQueryAlias(
    FinanceQueryAliasType type,
    String safeAlias,
    String resolvedValue,
    List<String> spokenAliases
) {
    public FinanceQueryAlias {
        Objects.requireNonNull(type, "type cannot be null");
        if (safeAlias == null || !safeAlias.matches("[a-z]+-[1-9][0-9]*")) {
            throw new IllegalArgumentException("safeAlias must be an opaque alias such as merchant-1");
        }
        if (!safeAlias.startsWith(type.name().toLowerCase(Locale.ROOT) + "-")) {
            throw new IllegalArgumentException("safeAlias must use its alias type prefix");
        }
        if (resolvedValue == null || resolvedValue.isBlank()) {
            throw new IllegalArgumentException("resolvedValue cannot be blank");
        }
        spokenAliases = List.copyOf(spokenAliases == null ? List.of() : spokenAliases);
        if (spokenAliases.stream().anyMatch(value -> value == null || value.isBlank())) {
            throw new IllegalArgumentException("spokenAliases cannot contain blank values");
        }
    }
}
