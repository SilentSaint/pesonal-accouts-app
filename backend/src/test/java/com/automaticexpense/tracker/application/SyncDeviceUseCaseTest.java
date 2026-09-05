package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.SyncDeviceUseCase;
import com.automaticexpense.tracker.application.port.out.WebSocketEventPublisher;
import com.automaticexpense.tracker.domain.SyncEvent;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;

class SyncDeviceUseCaseTest {

    private MockWebSocketEventPublisher publisher;
    private SyncDeviceUseCase syncUseCase;

    @BeforeEach
    void setUp() {
        publisher = new MockWebSocketEventPublisher();
        syncUseCase = new DeviceSyncService(publisher);
    }

    @Test
    void shouldRegisterAndUnregisterDeviceWebSocketConnections() {
        syncUseCase.registerConnection("conn-web-1", "user-100");
        syncUseCase.registerConnection("conn-mobile-2", "user-100");

        List<String> userConnections = syncUseCase.getActiveConnectionsForUser("user-100");
        assertThat(userConnections).containsExactlyInAnyOrder("conn-web-1", "conn-mobile-2");

        syncUseCase.unregisterConnection("conn-web-1");
        List<String> remaining = syncUseCase.getActiveConnectionsForUser("user-100");
        assertThat(remaining).containsExactly("conn-mobile-2");
    }

    @Test
    void shouldBroadcastSyncEventsToAllUserDevices() {
        syncUseCase.registerConnection("conn-mobile-1", "user-200");
        syncUseCase.registerConnection("conn-tablet-2", "user-200");

        SyncEvent event = new SyncEvent(
            "TRANSACTION_INGESTED",
            "txn-999",
            "{\"amount\": 450.00, \"merchant\": \"Swiggy\"}",
            LocalDateTime.now()
        );

        syncUseCase.broadcastEvent("user-200", event);

        assertThat(publisher.publishedEvents).hasSize(1);
        assertThat(publisher.publishedEvents.get(0).entityId()).isEqualTo("txn-999");
    }

    private static class MockWebSocketEventPublisher implements WebSocketEventPublisher {
        final List<SyncEvent> publishedEvents = new ArrayList<>();

        @Override
        public void broadcastToUser(String userId, SyncEvent event) {
            publishedEvents.add(event);
        }
    }
}
