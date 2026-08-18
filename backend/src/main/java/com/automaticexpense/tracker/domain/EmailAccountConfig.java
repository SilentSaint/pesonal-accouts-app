package com.automaticexpense.tracker.domain;

import java.time.LocalDateTime;
import java.util.Objects;

public class EmailAccountConfig {
    private final String emailAddress;
    private final String status;
    private final LocalDateTime linkedAt;

    public EmailAccountConfig(String emailAddress, String status, LocalDateTime linkedAt) {
        this.emailAddress = Objects.requireNonNull(emailAddress, "emailAddress cannot be null");
        this.status = status != null ? status : "CONNECTED";
        this.linkedAt = linkedAt != null ? linkedAt : LocalDateTime.now();
    }

    public boolean isActive() {
        return "PUSH_ACTIVE".equalsIgnoreCase(status) || "CONNECTED".equalsIgnoreCase(status);
    }

    public String emailAddress() {
        return emailAddress;
    }

    public String status() {
        return status;
    }

    public LocalDateTime linkedAt() {
        return linkedAt;
    }
}
