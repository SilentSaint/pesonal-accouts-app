package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.SyncEvent;

import java.util.List;

public interface SyncDeviceUseCase {
    void registerConnection(String connectionId, String userId);
    void unregisterConnection(String connectionId);
    void broadcastEvent(String userId, SyncEvent event);
    List<String> getActiveConnectionsForUser(String userId);
}
