package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.SecuritySessionUseCase;
import com.automaticexpense.tracker.domain.UserSession;

import java.time.LocalDateTime;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

public class SecuritySessionService implements SecuritySessionUseCase {

    private final Map<String, UserSession> sessionStore = new ConcurrentHashMap<>();

    @Override
    public UserSession createSession(String userId, int timeoutMinutes) {
        Objects.requireNonNull(userId, "userId cannot be null");
        String sessionId = UUID.randomUUID().toString();
        UserSession session = new UserSession(sessionId, userId, timeoutMinutes);
        sessionStore.put(sessionId, session);
        return session;
    }

    @Override
    public Optional<UserSession> validateAndTouchSession(String sessionId) {
        if (sessionId == null) return Optional.empty();
        UserSession session = sessionStore.get(sessionId);
        if (session == null || session.isExpired(LocalDateTime.now())) {
            if (session != null) {
                sessionStore.remove(sessionId);
            }
            return Optional.empty();
        }
        session.touch();
        return Optional.of(session);
    }

    @Override
    public void invalidateSession(String sessionId) {
        if (sessionId != null) {
            UserSession session = sessionStore.get(sessionId);
            if (session != null) {
                session.revoke();
                sessionStore.remove(sessionId);
            }
        }
    }
}
