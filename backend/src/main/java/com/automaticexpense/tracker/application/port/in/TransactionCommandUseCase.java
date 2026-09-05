package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.TransactionId;

import java.util.Optional;

public interface TransactionCommandUseCase {
    TransactionCommandStatusView submit(
        String userScopeId,
        TransactionId commandId,
        IngestTransactionCommand command
    );

    Optional<TransactionCommandStatusView> status(String userScopeId, TransactionId commandId);
}
