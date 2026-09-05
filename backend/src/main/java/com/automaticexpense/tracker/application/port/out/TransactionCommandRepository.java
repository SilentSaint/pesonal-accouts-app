package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.application.TransactionCommand;
import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.automaticexpense.tracker.domain.TransactionCommandStatus;
import com.automaticexpense.tracker.domain.TransactionId;

import java.util.Optional;

public interface TransactionCommandRepository {
    boolean create(TransactionCommand command);
    Optional<TransactionCommand> find(String userScopeId, TransactionId id);
    boolean markEnqueued(TransactionCommandReference reference);
    default boolean retry(TransactionCommandReference reference) {
        return false;
    }
    boolean claim(TransactionCommandReference reference);
    boolean finish(
        TransactionCommandReference reference,
        TransactionCommandStatus status,
        String failureReason
    );
}
