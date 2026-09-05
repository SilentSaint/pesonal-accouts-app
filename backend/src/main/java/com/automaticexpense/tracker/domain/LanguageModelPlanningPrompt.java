package com.automaticexpense.tracker.domain;

import java.util.List;
import java.util.Objects;

public record LanguageModelPlanningPrompt(
    String sanitizedQuestion,
    List<FinanceQueryCapability> allowedCapabilities,
    List<String> merchantAliases,
    List<String> categoryAliases,
    List<String> accountAliases
) {
    public LanguageModelPlanningPrompt {
        if (sanitizedQuestion == null || sanitizedQuestion.isBlank()) {
            throw new IllegalArgumentException("sanitizedQuestion cannot be blank");
        }
        if (sanitizedQuestion.length() > 500) {
            throw new IllegalArgumentException("sanitizedQuestion must be at most 500 characters");
        }
        allowedCapabilities = List.copyOf(Objects.requireNonNull(
            allowedCapabilities, "allowedCapabilities cannot be null"
        ));
        merchantAliases = validAliases(merchantAliases, "merchantAliases");
        categoryAliases = validAliases(categoryAliases, "categoryAliases");
        accountAliases = validAliases(accountAliases, "accountAliases");
    }

    private static List<String> validAliases(List<String> aliases, String name) {
        List<String> values = List.copyOf(aliases == null ? List.of() : aliases);
        if (values.stream().anyMatch(alias -> !alias.matches("[a-z]+-[1-9][0-9]*"))) {
            throw new IllegalArgumentException(name + " must only contain opaque aliases");
        }
        if (values.size() > 100) {
            throw new IllegalArgumentException(name + " must contain at most 100 aliases");
        }
        return values;
    }
}
