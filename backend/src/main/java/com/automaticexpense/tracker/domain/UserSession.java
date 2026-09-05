package com.automaticexpense.tracker.domain;

import java.time.LocalDateTime;
import java.util.Objects;

public class UserSession {
    private final String sessionId;
    private final String userId;
    private final LocalDateTime createdAt;
    private LocalDateTime lastActiveAt;
    private final int timeoutMinutes;
    private boolean isRevoked;

    public UserSession(String sessionId, String userId, int timeoutMinutes) {
        this(sessionId, userId, LocalDateTime.now(), LocalDateTime.now(), timeoutMinutes, false);
    }

    public UserSession(
        String sessionId,
        String userId,
        LocalDateTime createdAt,
        LocalDateTime lastActiveAt,
        int timeoutMinutes,
        boolean isRevoked
    ) {
        this.sessionId = Objects.requireNonNull(sessionId, "sessionId cannot be null");
        this.userId = Objects.requireNonNull(userId, "userId cannot be null");
        this.createdAt = createdAt != null ? createdAt : LocalDateTime.now();
        this.lastActiveAt = lastActiveAt != null ? lastActiveAt : LocalDateTime.now();
        this.timeoutMinutes = timeoutMinutes > 0 ? timeoutMinutes : 15;
        this.isRevoked = isRevoked;
    }

    public void touch() {
        if (!isRevoked) {
            this.lastActiveAt = LocalDateTime.now();
        }
    }

    public void revoke() {
        this.isRevoked = true;
    }

    public boolean isExpired(LocalDateTime now) {
        if (isRevoked) return true;
        return now.isAfter(lastActiveAt.plusMinutes(timeoutMinutes));
    }

    public String sessionId() {
        return sessionId;
    }

    public String userId() {
        return userId;
    }

    public LocalDateTime createdAt() {
        return createdAt;
    }

    public LocalDateTime lastActiveAt() {
        return lastActiveAt;
    }

    public int timeoutMinutes() {
        return timeoutMinutes;
    }

    public boolean isRevoked() {
        return isRevoked;
    }
}
