package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.SyncEvent;

public interface WebSocketEventPublisher {
    void broadcastToUser(String userId, SyncEvent event);
}
