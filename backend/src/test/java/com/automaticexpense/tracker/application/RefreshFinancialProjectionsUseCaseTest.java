package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.RefreshFinancialProjectionsRequest;
import com.automaticexpense.tracker.application.port.in.RefreshFinancialProjectionsResult;
import com.automaticexpense.tracker.application.port.in.RefreshFinancialProjectionsUseCase;
import com.automaticexpense.tracker.application.port.out.ProactiveInsightLedger;
import com.automaticexpense.tracker.application.port.out.ProactiveInsightRepository;
import com.automaticexpense.tracker.application.port.out.WebSocketEventPublisher;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class RefreshFinancialProjectionsUseCaseTest {

    @Test
    void persistsAndPublishesEachInsightOnlyOnceWhenTheSameRecalculationIsRetried() {
        InMemoryInsights repository = new InMemoryInsights();
        List<SyncEvent> published = new ArrayList<>();
        ProactiveInsightLedger ledger = (userId, asOf, timezone) -> snapshot(asOf, timezone);
        WebSocketEventPublisher events = (userId, event) -> published.add(event);
        RefreshFinancialProjectionsUseCase useCase = new RefreshFinancialProjectionsService(
            ledger, repository, new ProactiveInsightCalculator(), events
        );
        RefreshFinancialProjectionsRequest request = new RefreshFinancialProjectionsRequest(
            "user-1", Instant.parse("2026-08-31T12:00:00Z"), ZoneId.of("Asia/Kolkata"), "INR"
        );

        RefreshFinancialProjectionsResult first = useCase.refresh(request);
        RefreshFinancialProjectionsResult retry = useCase.refresh(request);

        assertThat(first.createdCount()).isGreaterThan(0);
        assertThat(retry.createdCount()).isZero();
        assertThat(repository.insights).hasSameSizeAs(first.insights());
        assertThat(published).hasSameSizeAs(first.insights());
        assertThat(published).allSatisfy(event -> assertThat(event.eventType()).isEqualTo("INSIGHT_UPSERTED"));
    }

    @Test
    void dismissesAnActiveInsightOnceAndPublishesThePersistedLifecycleChange() {
        InMemoryInsights repository = new InMemoryInsights();
        List<SyncEvent> published = new ArrayList<>();
        RefreshFinancialProjectionsService service = new RefreshFinancialProjectionsService(
            (userId, asOf, timezone) -> snapshot(asOf, timezone), repository,
            new ProactiveInsightCalculator(), (userId, event) -> published.add(event)
        );
        RefreshFinancialProjectionsRequest request = new RefreshFinancialProjectionsRequest(
            "user-1", Instant.parse("2026-08-31T12:00:00Z"), ZoneId.of("Asia/Kolkata"), "INR"
        );
        service.refresh(request);
        String id = repository.insights.values().iterator().next().id();

        service.dismiss("user-1", id);
        service.dismiss("user-1", id);

        assertThat(repository.insights.values()).filteredOn(insight -> insight.id().equals(id)).singleElement()
            .extracting(ProactiveInsight::lifecycleState)
            .isEqualTo(InsightLifecycleState.DISMISSED);
        assertThat(published).filteredOn(event -> event.eventType().equals("INSIGHT_DISMISSED"))
            .singleElement()
            .extracting(SyncEvent::entityId)
            .isEqualTo(id);
    }

    private FinancialSnapshot snapshot(Instant asOf, ZoneId timezone) {
        return new FinancialSnapshot(asOf, timezone, List.of(
            debit("current", "5000.00", "2026-08-12T10:00"),
            debit("july", "2000.00", "2026-07-12T10:00"),
            debit("june", "2000.00", "2026-06-12T10:00"),
            debit("may", "2000.00", "2026-05-12T10:00")
        ));
    }

    private Transaction debit(String id, String amount, String timestamp) {
        return new Transaction(
            new TransactionId(id), Money.of(amount, "INR"), TransactionType.DEBIT,
            LocalDateTime.parse(timestamp), "Grocer", new AccountId("account-1"), "GROCERIES",
            IngestionSource.MANUAL, ReconciliationStatus.CONFIRMED, Money.of(amount, "INR")
        );
    }

    private static final class InMemoryInsights implements ProactiveInsightRepository {
        private final Map<String, ProactiveInsight> insights = new LinkedHashMap<>();

        @Override
        public boolean saveIfAbsent(String userId, ProactiveInsight insight) {
            return insights.putIfAbsent(insight.deduplicationKey(), insight) == null;
        }

        @Override
        public List<ProactiveInsight> list(String userId) {
            return List.copyOf(insights.values());
        }

        @Override
        public void dismiss(String userId, String insightId) {
            insights.replaceAll((key, insight) -> insight.id().equals(insightId) ? insight.dismissed() : insight);
        }
    }
}
