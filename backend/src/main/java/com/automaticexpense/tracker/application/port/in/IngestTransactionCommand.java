package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.*;

import java.time.LocalDateTime;

public record IngestTransactionCommand(
    Money amount,
    TransactionType type,
    LocalDateTime timestamp,
    String merchantName,
    AccountId accountId,
    String categoryId,
    IngestionSource ingestionSource
) {}
