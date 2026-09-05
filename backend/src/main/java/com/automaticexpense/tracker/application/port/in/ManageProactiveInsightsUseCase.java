package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.ProactiveInsight;

import java.time.Instant;
import java.util.List;

public interface ManageProactiveInsightsUseCase {
    List<ProactiveInsight> list(String userId, Instant asOf, boolean includeDismissed);

    void dismiss(String userId, String insightId);
}
