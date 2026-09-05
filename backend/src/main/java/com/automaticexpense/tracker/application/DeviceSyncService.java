package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.SyncDeviceUseCase;
import com.automaticexpense.tracker.application.port.out.WebSocketEventPublisher;
import com.automaticexpense.tracker.domain.SyncEvent;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

public class DeviceSyncService implements SyncDeviceUseCase {

    private final WebSocketEventPublisher publisher;
    private final Map<String, String> connectionToUserMap = new ConcurrentHashMap<>();
    private final Map<String, Set<String>> userToConnectionsMap = new ConcurrentHashMap<>();

    public DeviceSyncService(WebSocketEventPublisher publisher) {
        this.publisher = Objects.requireNonNull(publisher, "publisher cannot be null");
    }

    @Override
    public void registerConnection(String connectionId, String userId) {
        Objects.requireNonNull(connectionId, "connectionId cannot be null");
        Objects.requireNonNull(userId, "userId cannot be null");

        connectionToUserMap.put(connectionId, userId);
        userToConnectionsMap.computeIfAbsent(userId, k -> ConcurrentHashMap.newKeySet()).add(connectionId);
    }

    @Override
    public void unregisterConnection(String connectionId) {
        if (connectionId == null) return;
        String userId = connectionToUserMap.remove(connectionId);
        if (userId != null) {
            Set<String> connections = userToConnectionsMap.get(userId);
            if (connections != null) {
                connections.remove(connectionId);
                if (connections.isEmpty()) {
                    userToConnectionsMap.remove(userId);
                }
            }
        }
    }

    @Override
    public void broadcastEvent(String userId, SyncEvent event) {
        Objects.requireNonNull(userId, "userId cannot be null");
        Objects.requireNonNull(event, "event cannot be null");
        publisher.broadcastToUser(userId, event);
    }

    @Override
    public List<String> getActiveConnectionsForUser(String userId) {
        if (userId == null) return Collections.emptyList();
        Set<String> connections = userToConnectionsMap.get(userId);
        return connections != null ? new ArrayList<>(connections) : Collections.emptyList();
    }
}
