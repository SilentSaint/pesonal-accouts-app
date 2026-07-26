package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record ParsedTransactionEvent(
    BigDecimal amount,
    String currency,
    TransactionType type,
    String accountLast4,
    String merchantName,
    LocalDateTime timestamp
) {}
