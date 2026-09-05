package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.application.port.in.TransactionCommandStatusView;
import com.automaticexpense.tracker.application.port.in.TransactionCommandUseCase;
import com.automaticexpense.tracker.application.port.out.TransactionCommandQueue;
import com.automaticexpense.tracker.application.port.out.TransactionCommandRepository;
import com.automaticexpense.tracker.application.port.out.TransactionIngestionExecutor;
import com.automaticexpense.tracker.application.port.out.WebSocketEventPublisher;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IngestionSource;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.automaticexpense.tracker.domain.TransactionCommandStatus;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.TransactionType;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

class TransactionCommandUseCaseTest {

    @Test
    void submitsOnceAndReplaysTheExistingPendingStatusForTheSameClientCommandId() {
        InMemoryCommands commands = new InMemoryCommands();
        RecordingQueue queue = new RecordingQueue();
        TransactionCommandUseCase useCase = new TransactionCommandService(commands, queue);
        TransactionId id = new TransactionId("client-command-001");

        TransactionCommandStatusView first = useCase.submit("user-scope", id, command());
        TransactionCommandStatusView retry = useCase.submit("user-scope", id, command());

        assertThat(first.status()).isEqualTo(TransactionCommandStatus.PENDING);
        assertThat(retry.status()).isEqualTo(TransactionCommandStatus.PENDING);
        assertThat(queue.references).containsExactly(new TransactionCommandReference("user-scope", id));
    }

    @Test
    void resubmitsAFailedCommandByRequeueingItsExistingReference() {
        InMemoryCommands commands = new InMemoryCommands();
        RecordingQueue queue = new RecordingQueue();
        TransactionCommandUseCase useCase = new TransactionCommandService(commands, queue);
        TransactionId id = new TransactionId("client-command-001");
        useCase.submit("user-scope", id, command());
        commands.finish(
            new TransactionCommandReference("user-scope", id),
            TransactionCommandStatus.FAILED,
            "Transaction could not be processed"
        );

        TransactionCommandStatusView retried = useCase.submit("user-scope", id, command());

        assertThat(retried.status()).isEqualTo(TransactionCommandStatus.PENDING);
        assertThat(queue.references).containsExactly(
            new TransactionCommandReference("user-scope", id),
            new TransactionCommandReference("user-scope", id)
        );
    }

    @Test
    void completesAClaimedCommandOnlyOnceWhenSqsDeliversItAgain() {
        InMemoryCommands commands = new InMemoryCommands();
        RecordingQueue queue = new RecordingQueue();
        TransactionCommandUseCase submissions = new TransactionCommandService(commands, queue);
        TransactionId id = new TransactionId("client-command-001");
        submissions.submit("user-scope", id, command());
        RecordingExecutor executor = new RecordingExecutor();
        TransactionCommandProcessor processor = new TransactionCommandProcessor(commands, executor);

        processor.process(new TransactionCommandReference("user-scope", id));
        processor.process(new TransactionCommandReference("user-scope", id));

        assertThat(executor.invocations).isEqualTo(1);
        assertThat(submissions.status("user-scope", id))
            .hasValueSatisfying(status -> assertThat(status.status())
                .isEqualTo(TransactionCommandStatus.COMPLETED));
    }

    @Test
    void publishesTheCanonicalTransactionAfterTheCommandCompletes() {
        InMemoryCommands commands = new InMemoryCommands();
        TransactionCommandUseCase submissions = new TransactionCommandService(commands, new RecordingQueue());
        TransactionId id = new TransactionId("client-command-002");
        submissions.submit("user-scope", id, command());
        RecordingEvents events = new RecordingEvents();

        new TransactionCommandProcessor(commands, new RecordingExecutor(), events)
            .process(new TransactionCommandReference("user-scope", id));

        assertThat(events.lastEvent.entityId()).isEqualTo("client-command-002");
        assertThat(events.lastUserId).isEqualTo("user-scope");
    }

    private IngestTransactionCommand command() {
        return new IngestTransactionCommand(
            Money.of("125.00", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 8, 29, 6, 0),
            "Coffee Shop",
            new AccountId("acc-1001"),
            null,
            IngestionSource.MANUAL
        );
    }

    private static final class RecordingQueue implements TransactionCommandQueue {
        private final java.util.List<TransactionCommandReference> references = new java.util.ArrayList<>();

        @Override
        public void enqueue(TransactionCommandReference reference) {
            references.add(reference);
        }
    }

    private static final class RecordingExecutor implements TransactionIngestionExecutor {
        private int invocations;

        @Override
        public Transaction ingest(TransactionCommand command) {
            invocations++;
            return new Transaction(
                command.id(), command.payload().amount(), command.payload().type(),
                command.payload().timestamp(), command.payload().merchantName(),
                command.payload().accountId(), command.payload().categoryId(),
                command.payload().ingestionSource(), ReconciliationStatus.CONFIRMED,
                command.payload().amount()
            );
        }

    }

    private static final class RecordingEvents implements WebSocketEventPublisher {
        private String lastUserId;
        private com.automaticexpense.tracker.domain.SyncEvent lastEvent;

        @Override
        public void broadcastToUser(String userId, com.automaticexpense.tracker.domain.SyncEvent event) {
            lastUserId = userId;
            lastEvent = event;
        }
    }

    private static final class InMemoryCommands implements TransactionCommandRepository {
        private final Map<String, TransactionCommand> values = new HashMap<>();

        @Override
        public boolean create(TransactionCommand command) {
            return values.putIfAbsent(key(command.userScopeId(), command.id()), command) == null;
        }

        @Override
        public Optional<TransactionCommand> find(String userScopeId, TransactionId id) {
            return Optional.ofNullable(values.get(key(userScopeId, id)));
        }

        @Override
        public boolean markEnqueued(TransactionCommandReference reference) {
            String key = key(reference.userScopeId(), reference.commandId());
            TransactionCommand existing = values.get(key);
            if (existing == null || existing.enqueued()) {
                return false;
            }
            values.put(key, existing.asEnqueued());
            return true;
        }

        @Override
        public boolean retry(TransactionCommandReference reference) {
            String key = key(reference.userScopeId(), reference.commandId());
            TransactionCommand existing = values.get(key);
            if (existing == null || existing.status() != TransactionCommandStatus.FAILED) {
                return false;
            }
            values.put(key, new TransactionCommand(
                existing.userScopeId(),
                existing.id(),
                existing.payload(),
                TransactionCommandStatus.PENDING,
                null,
                false
            ));
            return true;
        }

        @Override
        public boolean claim(TransactionCommandReference reference) {
            TransactionCommand claimed = values.computeIfPresent(
                key(reference.userScopeId(), reference.commandId()), (key, command) ->
                command.status().isTerminal() ? command : command.withStatus(TransactionCommandStatus.PROCESSING, null)
            );
            return claimed != null && claimed.status() == TransactionCommandStatus.PROCESSING;
        }

        @Override
        public boolean finish(TransactionCommandReference reference, TransactionCommandStatus status, String failureReason) {
            return values.computeIfPresent(key(reference.userScopeId(), reference.commandId()), (key, command) ->
                command.withStatus(status, failureReason)
            ) != null;
        }

        private String key(String userScopeId, TransactionId id) {
            return userScopeId + ":" + id.value();
        }
    }
}
