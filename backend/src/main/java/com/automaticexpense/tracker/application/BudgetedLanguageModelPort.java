package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.out.LanguageModelPort;
import com.automaticexpense.tracker.application.port.out.LanguageModelUsageRepository;
import com.automaticexpense.tracker.domain.LanguageModelPlanningPrompt;
import com.automaticexpense.tracker.domain.LanguageModelPlanningResponse;

import java.time.Clock;
import java.time.YearMonth;
import java.util.Objects;

/**
 * Limits paid planning attempts using durable, month-scoped reservations.
 */
public final class BudgetedLanguageModelPort implements LanguageModelPort {
    private final LanguageModelPort delegate;
    private final LanguageModelUsageRepository usage;
    private final String provider;
    private final int maximumRequestsPerMonth;
    private final Clock clock;

    public BudgetedLanguageModelPort(
        LanguageModelPort delegate,
        LanguageModelUsageRepository usage,
        String provider,
        int maximumRequestsPerMonth,
        Clock clock
    ) {
        this.delegate = Objects.requireNonNull(delegate, "delegate cannot be null");
        this.usage = Objects.requireNonNull(usage, "usage cannot be null");
        if (provider == null || provider.isBlank()) {
            throw new IllegalArgumentException("provider cannot be blank");
        }
        if (maximumRequestsPerMonth < 1) {
            throw new IllegalArgumentException("maximumRequestsPerMonth must be positive");
        }
        this.provider = provider;
        this.maximumRequestsPerMonth = maximumRequestsPerMonth;
        this.clock = Objects.requireNonNull(clock, "clock cannot be null");
    }

    @Override
    public LanguageModelPlanningResponse plan(LanguageModelPlanningPrompt prompt) {
        if (!usage.reserve(provider, YearMonth.now(clock), maximumRequestsPerMonth)) {
            return LanguageModelPlanningResponse.unavailable();
        }
        try {
            return delegate.plan(prompt);
        } catch (RuntimeException exception) {
            return LanguageModelPlanningResponse.unavailable();
        }
    }
}
