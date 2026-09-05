package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.SecuritySessionUseCase;
import com.automaticexpense.tracker.domain.UserSession;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

class SecuritySessionUseCaseTest {

    private SecuritySessionUseCase sessionUseCase;

    @BeforeEach
    void setUp() {
        sessionUseCase = new SecuritySessionService();
    }

    @Test
    void shouldCreateValidateAndInvalidateSession() {
        UserSession session = sessionUseCase.createSession("user-123", 15);
        assertThat(session.sessionId()).isNotBlank();
        assertThat(session.userId()).isEqualTo("user-123");

        Optional<UserSession> valid = sessionUseCase.validateAndTouchSession(session.sessionId());
        assertThat(valid).isPresent();

        sessionUseCase.invalidateSession(session.sessionId());
        Optional<UserSession> invalid = sessionUseCase.validateAndTouchSession(session.sessionId());
        assertThat(invalid).isEmpty();
    }
}
