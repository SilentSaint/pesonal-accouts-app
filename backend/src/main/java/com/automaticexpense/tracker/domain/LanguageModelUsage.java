package com.automaticexpense.tracker.domain;

import java.time.Duration;
import java.util.Objects;

public record LanguageModelUsage(
    String provider,
    String model,
    Outcome outcome,
    Duration latency,
    int promptTokenCount,
    int responseTokenCount
) {
    public enum Outcome {
        PLANNED,
        INVALID,
        UNAVAILABLE
    }

    public LanguageModelUsage {
        if (provider == null || provider.isBlank()) {
            throw new IllegalArgumentException("provider cannot be blank");
        }
        if (model == null || model.isBlank()) {
            throw new IllegalArgumentException("model cannot be blank");
        }
        Objects.requireNonNull(outcome, "outcome cannot be null");
        Objects.requireNonNull(latency, "latency cannot be null");
        if (latency.isNegative() || promptTokenCount < 0 || responseTokenCount < 0) {
            throw new IllegalArgumentException("usage values cannot be negative");
        }
    }
}
