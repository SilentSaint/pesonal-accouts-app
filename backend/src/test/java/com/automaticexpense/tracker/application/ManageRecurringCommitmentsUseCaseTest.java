package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ManageRecurringCommitmentsUseCase;
import com.automaticexpense.tracker.application.port.out.RecurringCommitmentRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IngestionSource;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.RecurringCommitment;
import com.automaticexpense.tracker.domain.RecurringCommitmentStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.TransactionType;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

class ManageRecurringCommitmentsUseCaseTest {

    @Test
    void detectsARecurringDebitAsAnUnconfirmedCandidateUntilTheUserConfirmsIt() {
        InMemoryTransactions transactions = new InMemoryTransactions();
        transactions.save(debit("streaming-jan", "StreamFlix", "499.00", LocalDateTime.of(2026, 1, 5, 9, 0)));
        transactions.save(debit("streaming-feb", "StreamFlix", "499.00", LocalDateTime.of(2026, 2, 5, 9, 0)));
        transactions.save(debit("streaming-mar", "StreamFlix", "499.00", LocalDateTime.of(2026, 3, 5, 9, 0)));
        ManageRecurringCommitmentsUseCase commitments = new RecurringCommitmentService(
            new InMemoryCommitments(), transactions
        );

        List<RecurringCommitment> candidates = commitments.detectCandidates(LocalDate.of(2026, 3, 6));

        assertThat(candidates).singleElement().satisfies(candidate -> {
            assertThat(candidate.status()).isEqualTo(RecurringCommitmentStatus.CANDIDATE);
            assertThat(candidate.expectedAmountRange().minimum()).isEqualTo(Money.of("499.00", "INR"));
            assertThat(candidate.expectedAmountRange().maximum()).isEqualTo(Money.of("499.00", "INR"));
            assertThat(candidate.nextPaymentDate()).isEqualTo(LocalDate.of(2026, 4, 5));
            assertThat(candidate.supportingTransactionIds()).containsExactlyInAnyOrder(
                new TransactionId("streaming-jan"),
                new TransactionId("streaming-feb"),
                new TransactionId("streaming-mar")
            );
        });

        RecurringCommitment confirmed = commitments.confirm(candidates.getFirst().id());

        assertThat(confirmed.status()).isEqualTo(RecurringCommitmentStatus.CONFIRMED);
        assertThat(commitments.list(LocalDate.of(2026, 3, 6))).contains(confirmed);
        assertThat(transactions.findById(new TransactionId("streaming-jan")).orElseThrow().merchantName())
            .isEqualTo("StreamFlix");
    }

    private static Transaction debit(String id, String merchant, String amount, LocalDateTime timestamp) {
        return new Transaction(
            new TransactionId(id), Money.of(amount, "INR"), TransactionType.DEBIT, timestamp, merchant,
            new AccountId("card-1"), null, IngestionSource.SMS, ReconciliationStatus.CONFIRMED,
            Money.of(amount, "INR")
        );
    }

    private static final class InMemoryCommitments implements RecurringCommitmentRepository {
        private final List<RecurringCommitment> commitments = new ArrayList<>();

        @Override
        public void save(RecurringCommitment commitment) {
            commitments.removeIf(existing -> existing.id().equals(commitment.id()));
            commitments.add(commitment);
        }

        @Override
        public Optional<RecurringCommitment> findById(String commitmentId) {
            return commitments.stream().filter(commitment -> commitment.id().equals(commitmentId)).findFirst();
        }

        @Override
        public Optional<RecurringCommitment> findByCandidateKey(String candidateKey) {
            return commitments.stream()
                .filter(commitment -> candidateKey.equals(commitment.candidateKey()))
                .findFirst();
        }

        @Override
        public List<RecurringCommitment> findAll() {
            return List.copyOf(commitments);
        }
    }

    private static final class InMemoryTransactions implements TransactionRepository {
        private final List<Transaction> transactions = new ArrayList<>();

        @Override public void save(Transaction transaction) { transactions.add(transaction); }
        @Override public Optional<Transaction> findById(TransactionId id) {
            return transactions.stream().filter(transaction -> transaction.id().equals(id)).findFirst();
        }
        @Override public List<Transaction> findByAccountId(AccountId accountId) { return List.of(); }
        @Override public List<Transaction> findByReconciliationStatus(ReconciliationStatus status) { return List.of(); }
        @Override public List<Transaction> findByAccountIdAndWindow(
            AccountId accountId, LocalDateTime start, LocalDateTime end
        ) { return List.of(); }
        @Override public List<Transaction> findAllTransactions() { return List.copyOf(transactions); }
        @Override public void delete(TransactionId id) {}
    }
}
