package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class EmailAccountConfigTest {

    @Test
    void shouldCreateLinkedEmailAccountConfig() {
        EmailAccountConfig config = new EmailAccountConfig(
            "user@gmail.com",
            "PUSH_ACTIVE",
            LocalDateTime.now()
        );

        assertThat(config.emailAddress()).isEqualTo("user@gmail.com");
        assertThat(config.status()).isEqualTo("PUSH_ACTIVE");
        assertThat(config.isActive()).isTrue();
    }
}
