package com.automaticexpense.tracker.domain;

public record LanguageModelPlanningResponse(
    Status status,
    String capability,
    String period,
    String merchantAlias,
    String categoryAlias,
    String accountAlias
) {
    public enum Status {
        PLANNED,
        UNAVAILABLE,
        INVALID
    }

    public static LanguageModelPlanningResponse unavailable() {
        return new LanguageModelPlanningResponse(Status.UNAVAILABLE, null, null, null, null, null);
    }

    public static LanguageModelPlanningResponse invalid() {
        return new LanguageModelPlanningResponse(Status.INVALID, null, null, null, null, null);
    }
}
