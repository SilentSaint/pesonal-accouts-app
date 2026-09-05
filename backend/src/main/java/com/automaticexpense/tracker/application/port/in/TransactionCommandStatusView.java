package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.TransactionCommandStatus;
import com.automaticexpense.tracker.domain.TransactionId;

public record TransactionCommandStatusView(
    TransactionId id,
    TransactionCommandStatus status,
    String failureReason
) {
}
