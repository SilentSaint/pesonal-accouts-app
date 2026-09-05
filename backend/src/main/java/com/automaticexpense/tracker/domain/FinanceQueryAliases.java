package com.automaticexpense.tracker.domain;

import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Optional;

public record FinanceQueryAliases(List<FinanceQueryAlias> entries) {
    public FinanceQueryAliases {
        entries = List.copyOf(entries == null ? List.of() : entries);
        long distinct = entries.stream().map(FinanceQueryAlias::safeAlias).distinct().count();
        if (distinct != entries.size()) {
            throw new IllegalArgumentException("safe aliases must be unique");
        }
    }

    public Optional<FinanceQueryAlias> bySafeAlias(FinanceQueryAliasType type, String safeAlias) {
        return entries.stream()
            .filter(entry -> entry.type() == type && entry.safeAlias().equals(safeAlias))
            .findFirst();
    }

    public List<String> safeAliases(FinanceQueryAliasType type) {
        return entries.stream()
            .filter(entry -> entry.type() == type)
            .map(FinanceQueryAlias::safeAlias)
            .toList();
    }

    public List<FinanceQueryAlias> matchingSpokenAlias(FinanceQueryAliasType type, String question) {
        Objects.requireNonNull(question, "question cannot be null");
        String normalizedQuestion = question.toLowerCase(Locale.ROOT);
        return entries.stream()
            .filter(entry -> entry.type() == type)
            .filter(entry -> entry.spokenAliases().stream().anyMatch(alias ->
                normalizedQuestion.contains(alias.toLowerCase(Locale.ROOT))
            ))
            .toList();
    }
}
