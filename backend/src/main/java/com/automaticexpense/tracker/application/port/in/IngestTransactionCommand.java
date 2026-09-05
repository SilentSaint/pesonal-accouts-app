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
    IngestionSource ingestionSource,
    String subCategory,
    Money netPersonalExpense,
    String accountMask,
    String referenceNumber,
    String rawSnippet,
    String transferCounterpartMask
) {
    public IngestTransactionCommand(
        Money amount,
        TransactionType type,
        LocalDateTime timestamp,
        String merchantName,
        AccountId accountId,
        String categoryId,
        IngestionSource ingestionSource
    ) {
        this(
            amount, type, timestamp, merchantName, accountId, categoryId,
            ingestionSource, null, amount, null, null, null, null
        );
    }
}
