package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.ParsedTransactionEvent;
import java.time.LocalDateTime;

public interface IngestSmsTransactionUseCase {
    ParsedTransactionEvent ingestSms(String sender, String body, LocalDateTime receivedAt);
}
