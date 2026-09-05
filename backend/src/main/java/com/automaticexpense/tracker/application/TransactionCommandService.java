package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.application.port.in.TransactionCommandStatusView;
import com.automaticexpense.tracker.application.port.in.TransactionCommandUseCase;
import com.automaticexpense.tracker.application.port.out.TransactionCommandQueue;
import com.automaticexpense.tracker.application.port.out.TransactionCommandRepository;
import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.automaticexpense.tracker.domain.TransactionCommandStatus;
import com.automaticexpense.tracker.domain.TransactionId;

import java.util.Objects;
import java.util.Optional;
import java.util.regex.Pattern;

public final class TransactionCommandService implements TransactionCommandUseCase {
    private static final Pattern CLIENT_COMMAND_ID = Pattern.compile("[A-Za-z0-9][A-Za-z0-9_-]{7,127}");

    private final TransactionCommandRepository repository;
    private final TransactionCommandQueue queue;

    public TransactionCommandService(TransactionCommandRepository repository, TransactionCommandQueue queue) {
        this.repository = Objects.requireNonNull(repository, "repository cannot be null");
        this.queue = Objects.requireNonNull(queue, "queue cannot be null");
    }

    @Override
    public TransactionCommandStatusView submit(
        String userScopeId,
        TransactionId commandId,
        IngestTransactionCommand payload
    ) {
        validateCommandId(commandId);
        TransactionCommand command = new TransactionCommand(
            userScopeId, commandId, payload, TransactionCommandStatus.PENDING, null, false
        );
        if (repository.create(command)) {
            enqueueAndMark(command.reference());
            return repository.find(userScopeId, commandId)
                .map(this::view)
                .orElseThrow(() -> new IllegalStateException("Enqueued command was not found"));
        }

        TransactionCommand existing = repository.find(userScopeId, commandId)
            .orElseThrow(() -> new IllegalStateException("Command creation did not persist"));
        if (existing.status() == TransactionCommandStatus.FAILED
            && repository.retry(existing.reference())) {
            enqueueAndMark(existing.reference());
            existing = repository.find(userScopeId, commandId).orElseThrow();
        }
        if (!existing.enqueued() && !existing.status().isTerminal()) {
            enqueueAndMark(existing.reference());
            existing = repository.find(userScopeId, commandId).orElseThrow();
        }
        return view(existing);
    }

    @Override
    public Optional<TransactionCommandStatusView> status(String userScopeId, TransactionId commandId) {
        validateCommandId(commandId);
        return repository.find(userScopeId, commandId).map(this::view);
    }

    private void enqueueAndMark(TransactionCommandReference reference) {
        queue.enqueue(reference);
        repository.markEnqueued(reference);
    }

    private TransactionCommandStatusView view(TransactionCommand command) {
        return new TransactionCommandStatusView(command.id(), command.status(), command.failureReason());
    }

    private void validateCommandId(TransactionId commandId) {
        Objects.requireNonNull(commandId, "commandId cannot be null");
        if (!CLIENT_COMMAND_ID.matcher(commandId.value()).matches()) {
            throw new IllegalArgumentException("Invalid command id");
        }
    }
}
