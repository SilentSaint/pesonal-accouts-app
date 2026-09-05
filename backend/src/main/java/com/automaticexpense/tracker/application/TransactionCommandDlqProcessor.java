package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.FailTransactionCommandUseCase;
import com.automaticexpense.tracker.application.port.out.TransactionCommandRepository;
import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.automaticexpense.tracker.domain.TransactionCommandStatus;

import java.util.Objects;

/**
 * Completes commands stranded after primary FIFO retry exhaustion.
 */
public final class TransactionCommandDlqProcessor implements FailTransactionCommandUseCase {
    public static final String FAILURE_REASON = "Transaction could not be processed";

    private final TransactionCommandRepository repository;

    public TransactionCommandDlqProcessor(TransactionCommandRepository repository) {
        this.repository = Objects.requireNonNull(repository, "repository cannot be null");
    }

    @Override
    public void failAfterRetryExhaustion(TransactionCommandReference reference) {
        repository.finish(reference, TransactionCommandStatus.FAILED, FAILURE_REASON);
    }
}
