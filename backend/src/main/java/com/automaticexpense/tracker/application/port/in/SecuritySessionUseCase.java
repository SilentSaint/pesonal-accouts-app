package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.UserSession;

import java.util.Optional;

public interface SecuritySessionUseCase {
    UserSession createSession(String userId, int timeoutMinutes);
    Optional<UserSession> validateAndTouchSession(String sessionId);
    void invalidateSession(String sessionId);
}
