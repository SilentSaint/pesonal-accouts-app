package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.out.TransactionCommandRepository;
import com.automaticexpense.tracker.application.port.out.TransactionIngestionExecutor;
import com.automaticexpense.tracker.application.port.out.WebSocketEventPublisher;
import com.automaticexpense.tracker.application.port.in.ProcessTransactionCommandUseCase;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.automaticexpense.tracker.domain.TransactionCommandStatus;
import com.automaticexpense.tracker.domain.SyncEvent;

import java.util.Objects;
import java.time.LocalDateTime;
import java.util.logging.Level;
import java.util.logging.Logger;

public final class TransactionCommandProcessor implements ProcessTransactionCommandUseCase {
    private static final String REJECTED_REASON = "Transaction could not be processed";
    private static final Logger LOG = Logger.getLogger(TransactionCommandProcessor.class.getName());

    private final TransactionCommandRepository repository;
    private final TransactionIngestionExecutor ingestionExecutor;
    private final WebSocketEventPublisher syncEvents;

    public TransactionCommandProcessor(
        TransactionCommandRepository repository,
        TransactionIngestionExecutor ingestionExecutor
    ) {
        this(repository, ingestionExecutor, (userId, event) -> { });
    }

    public TransactionCommandProcessor(
        TransactionCommandRepository repository,
        TransactionIngestionExecutor ingestionExecutor,
        WebSocketEventPublisher syncEvents
    ) {
        this.repository = Objects.requireNonNull(repository, "repository cannot be null");
        this.ingestionExecutor = Objects.requireNonNull(ingestionExecutor, "ingestionExecutor cannot be null");
        this.syncEvents = Objects.requireNonNull(syncEvents, "syncEvents cannot be null");
    }

    @Override
    public void process(TransactionCommandReference reference) {
        if (!repository.claim(reference)) {
            LOG.log(
                Level.INFO,
                "event=transaction_command outcome=skipped commandId={0}",
                reference.commandId().value()
            );
            return;
        }
        TransactionCommand command = repository.find(reference.userScopeId(), reference.commandId())
            .orElseThrow(() -> new IllegalStateException("Claimed command was not found"));
        try {
            Transaction transaction = ingestionExecutor.ingest(command);
            TransactionCommandStatus status = transaction.reconciliationStatus() == ReconciliationStatus.NEEDS_REVIEW
                ? TransactionCommandStatus.NEEDS_REVIEW
                : TransactionCommandStatus.COMPLETED;
            if (!repository.finish(reference, status, null)) {
                throw new IllegalStateException("Unable to complete claimed command");
            }
            LOG.log(
                Level.INFO,
                "event=transaction_command outcome=completed commandId={0} status={1}",
                new Object[] {command.id().value(), status.name()}
            );
            try {
                syncEvents.broadcastToUser(command.userScopeId(), new SyncEvent(
                    "TRANSACTION_UPSERTED",
                    transaction.id().value(),
                    "{\"id\":\"" + transaction.id().value().replace("\"", "\\\"") + "\"}",
                    LocalDateTime.now()
                ));
            } catch (RuntimeException exception) {
                System.err.println("Canonical sync event delivery failed: " + exception.getMessage());
            }
        } catch (CommandRejectedException exception) {
            if (!repository.finish(reference, TransactionCommandStatus.FAILED, REJECTED_REASON)) {
                throw new IllegalStateException("Unable to fail claimed command", exception);
            }
            LOG.log(
                Level.WARNING,
                "event=transaction_command outcome=rejected commandId={0} exception={1}",
                new Object[] {command.id().value(), exception.getClass().getSimpleName()}
            );
        }
    }
}
