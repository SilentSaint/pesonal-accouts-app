package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class UserSessionTest {

    @Test
    void shouldTrackSessionActivityAndExpireOnIdleTimeout() {
        LocalDateTime baseTime = LocalDateTime.of(2026, 8, 25, 12, 0);
        UserSession session = new UserSession(
            "sess-100",
            "user-1",
            baseTime,
            baseTime,
            5,
            false
        );

        assertThat(session.isExpired(baseTime.plusMinutes(4))).isFalse();
        assertThat(session.isExpired(baseTime.plusMinutes(6))).isTrue();

        session.touch();
        assertThat(session.isRevoked()).isFalse();

        session.revoke();
        assertThat(session.isExpired(baseTime.plusMinutes(1))).isTrue();
    }
}
