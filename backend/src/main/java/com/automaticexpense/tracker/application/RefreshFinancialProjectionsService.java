package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ManageProactiveInsightsUseCase;
import com.automaticexpense.tracker.application.port.in.RefreshFinancialProjectionsRequest;
import com.automaticexpense.tracker.application.port.in.RefreshFinancialProjectionsResult;
import com.automaticexpense.tracker.application.port.in.RefreshFinancialProjectionsUseCase;
import com.automaticexpense.tracker.application.port.out.ProactiveInsightLedger;
import com.automaticexpense.tracker.application.port.out.ProactiveInsightRepository;
import com.automaticexpense.tracker.application.port.out.WebSocketEventPublisher;
import com.automaticexpense.tracker.domain.ProactiveInsight;
import com.automaticexpense.tracker.domain.ProactiveInsightCalculator;
import com.automaticexpense.tracker.domain.ProactiveInsightRequest;
import com.automaticexpense.tracker.domain.SyncEvent;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Objects;

public final class RefreshFinancialProjectionsService
    implements RefreshFinancialProjectionsUseCase, ManageProactiveInsightsUseCase {

    private final ProactiveInsightLedger ledger;
    private final ProactiveInsightRepository repository;
    private final ProactiveInsightCalculator calculator;
    private final WebSocketEventPublisher syncEvents;

    public RefreshFinancialProjectionsService(
        ProactiveInsightLedger ledger,
        ProactiveInsightRepository repository,
        ProactiveInsightCalculator calculator,
        WebSocketEventPublisher syncEvents
    ) {
        this.ledger = Objects.requireNonNull(ledger, "ledger cannot be null");
        this.repository = Objects.requireNonNull(repository, "repository cannot be null");
        this.calculator = Objects.requireNonNull(calculator, "calculator cannot be null");
        this.syncEvents = Objects.requireNonNull(syncEvents, "syncEvents cannot be null");
    }

    @Override
    public RefreshFinancialProjectionsResult refresh(RefreshFinancialProjectionsRequest request) {
        Objects.requireNonNull(request, "request cannot be null");
        List<ProactiveInsight> insights = calculator.evaluate(
            ledger.load(request.userId(), request.asOf(), request.timezone()),
            new ProactiveInsightRequest(request.currency())
        );
        int created = 0;
        for (ProactiveInsight insight : insights) {
            if (repository.saveIfAbsent(request.userId(), insight)) {
                created++;
                syncEvents.broadcastToUser(request.userId(), new SyncEvent(
                    "INSIGHT_UPSERTED", insight.id(),
                    "{\"id\":\"" + insight.id() + "\",\"lifecycleState\":\"ACTIVE\"}",
                    LocalDateTime.ofInstant(request.asOf(), ZoneOffset.UTC)
                ));
            }
        }
        return new RefreshFinancialProjectionsResult(insights, created);
    }

    @Override
    public List<ProactiveInsight> list(String userId, Instant asOf, boolean includeDismissed) {
        if (userId == null || userId.isBlank()) throw new IllegalArgumentException("userId cannot be blank");
        Objects.requireNonNull(asOf, "asOf cannot be null");
        return repository.list(userId).stream()
            .filter(insight -> includeDismissed || insight.isCurrentAt(asOf))
            .toList();
    }

    @Override
    public void dismiss(String userId, String insightId) {
        if (userId == null || userId.isBlank()) throw new IllegalArgumentException("userId cannot be blank");
        if (insightId == null || insightId.isBlank()) throw new IllegalArgumentException("insightId cannot be blank");
        boolean active = repository.list(userId).stream()
            .anyMatch(insight -> insight.id().equals(insightId)
                && insight.lifecycleState() == com.automaticexpense.tracker.domain.InsightLifecycleState.ACTIVE);
        if (active) {
            repository.dismiss(userId, insightId);
            syncEvents.broadcastToUser(userId, new SyncEvent(
                "INSIGHT_DISMISSED", insightId,
                "{\"id\":\"" + insightId + "\",\"lifecycleState\":\"DISMISSED\"}",
                LocalDateTime.now()
            ));
        }
    }
}
