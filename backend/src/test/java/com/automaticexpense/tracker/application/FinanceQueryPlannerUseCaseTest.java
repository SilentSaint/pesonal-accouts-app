package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.domain.FinanceQuery;
import com.automaticexpense.tracker.domain.FinanceQueryAlias;
import com.automaticexpense.tracker.domain.FinanceQueryAliasType;
import com.automaticexpense.tracker.domain.FinanceQueryAliases;
import com.automaticexpense.tracker.domain.FinanceQueryCapability;
import com.automaticexpense.tracker.domain.FinanceQueryPlanningResult;
import com.automaticexpense.tracker.domain.PlannedFinanceQuery;
import com.automaticexpense.tracker.domain.LanguageModelPlanningResponse;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;

class FinanceQueryPlannerUseCaseTest {

    @Test
    void plansMerchantSpendingForTheCurrentMonthWithoutAHostedModel() {
        FinanceQueryPlannerService planner = new FinanceQueryPlannerService();
        FinanceQueryPlanningResult result = planner.plan(
            new FinanceQuery(
                "How much did I spend at corner shop this month?",
                Instant.parse("2026-08-29T12:00:00Z"),
                ZoneId.of("Asia/Kolkata"),
                "INR"
            ),
            new FinanceQueryAliases(List.of(
                new FinanceQueryAlias(
                    FinanceQueryAliasType.MERCHANT, "merchant-1", "Corner Shop", List.of("corner shop")
                )
            ))
        );

        assertThat(result).isInstanceOf(PlannedFinanceQuery.class);
        PlannedFinanceQuery planned = (PlannedFinanceQuery) result;
        assertThat(planned.plan().capability()).isEqualTo(FinanceQueryCapability.SPENDING_TOTAL);
        assertThat(planned.plan().filters().merchantName()).isEqualTo("Corner Shop");
        assertThat(planned.plan().filters().period()).isEqualTo(
            new com.automaticexpense.tracker.domain.DateRange(
                LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 31)
            )
        );
        assertThat(planned.usedHostedModel()).isFalse();
    }

    @Test
    void sendsOnlyOpaqueAliasesToTheHostedPlannerAndValidatesItsPlan() {
        FinanceQueryPlannerService planner = new FinanceQueryPlannerService(prompt -> {
            assertThat(prompt.sanitizedQuestion()).contains("merchant-1").doesNotContain("Corner Shop");
            assertThat(prompt.merchantAliases()).containsExactly("merchant-1");
            return new LanguageModelPlanningResponse(
                LanguageModelPlanningResponse.Status.PLANNED,
                "SPENDING_TOTAL",
                "CURRENT_MONTH",
                "merchant-1",
                null,
                null
            );
        });

        FinanceQueryPlanningResult result = planner.plan(
            new FinanceQuery(
                "What is the distribution of my outgoings at Corner Shop this month?",
                Instant.parse("2026-08-29T12:00:00Z"),
                ZoneId.of("Asia/Kolkata"),
                "INR"
            ),
            new FinanceQueryAliases(List.of(
                new FinanceQueryAlias(
                    FinanceQueryAliasType.MERCHANT, "merchant-1", "Corner Shop", List.of("corner shop")
                )
            ))
        );

        assertThat(result).isInstanceOf(PlannedFinanceQuery.class);
        PlannedFinanceQuery planned = (PlannedFinanceQuery) result;
        assertThat(planned.usedHostedModel()).isTrue();
        assertThat(planned.plan().filters().merchantName()).isEqualTo("Corner Shop");
    }

    @Test
    void requestsClarificationWhenTheHostedPlannerReturnsAnUnknownCapability() {
        FinanceQueryPlannerService planner = new FinanceQueryPlannerService(prompt ->
            new LanguageModelPlanningResponse(
                LanguageModelPlanningResponse.Status.PLANNED,
                "FORECAST_NEXT_MONTH",
                "CURRENT_MONTH",
                null,
                null,
                null
            )
        );

        FinanceQueryPlanningResult result = planner.plan(
            new FinanceQuery(
                "Summarize my position this month",
                Instant.parse("2026-08-29T12:00:00Z"),
                ZoneId.of("Asia/Kolkata"),
                "INR"
            ),
            new FinanceQueryAliases(List.of())
        );

        assertThat(result).isInstanceOf(com.automaticexpense.tracker.domain.FinanceQueryClarification.class);
    }

    @Test
    void requestsClarificationInsteadOfSendingAnAmbiguousContactReferenceToAProvider() {
        AtomicBoolean providerCalled = new AtomicBoolean();
        FinanceQueryPlannerService planner = new FinanceQueryPlannerService(prompt -> {
            providerCalled.set(true);
            return LanguageModelPlanningResponse.invalid();
        });

        FinanceQueryPlanningResult result = planner.plan(
            new FinanceQuery(
                "Summarize spending with Rahul this month",
                Instant.parse("2026-08-29T12:00:00Z"),
                ZoneId.of("Asia/Kolkata"),
                "INR"
            ),
            new FinanceQueryAliases(List.of())
        );

        assertThat(result).isInstanceOf(com.automaticexpense.tracker.domain.FinanceQueryClarification.class);
        assertThat(providerCalled).isFalse();
    }
}
