package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.domain.LanguageModelPlanningPrompt;
import com.automaticexpense.tracker.domain.LanguageModelPlanningResponse;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;

class BudgetedLanguageModelPortTest {

    @Test
    void degradesWithoutCallingTheProviderWhenMonthlyBudgetIsExhausted() {
        AtomicBoolean providerCalled = new AtomicBoolean();
        BudgetedLanguageModelPort port = new BudgetedLanguageModelPort(
            prompt -> {
                providerCalled.set(true);
                return LanguageModelPlanningResponse.invalid();
            },
            (provider, month, maximum) -> false,
            "GEMINI",
            50,
            Clock.fixed(Instant.parse("2026-08-01T00:00:00Z"), ZoneOffset.UTC)
        );

        LanguageModelPlanningResponse response = port.plan(new LanguageModelPlanningPrompt(
            "summarize spending",
            List.of(),
            List.of(),
            List.of(),
            List.of()
        ));

        assertThat(response.status()).isEqualTo(LanguageModelPlanningResponse.Status.UNAVAILABLE);
        assertThat(providerCalled).isFalse();
    }
}
