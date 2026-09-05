package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.ProactiveInsight;

import java.util.List;

public interface ProactiveInsightRepository {
    boolean saveIfAbsent(String userId, ProactiveInsight insight);

    List<ProactiveInsight> list(String userId);

    void dismiss(String userId, String insightId);
}
