package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ContactDebtSummary;
import com.automaticexpense.tracker.application.port.in.ContactSplitRequest;
import com.automaticexpense.tracker.application.port.in.ManagePeerDebtUseCase;
import com.automaticexpense.tracker.application.port.out.PeerDebtRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ManagePeerDebtUseCaseTest {

    private InMemoryPeerDebtRepository peerDebtRepository;
    private InMemoryTransactionRepository transactionRepository;
    private ManagePeerDebtUseCase peerDebtUseCase;

    @BeforeEach
    void setUp() {
        peerDebtRepository = new InMemoryPeerDebtRepository();
        transactionRepository = new InMemoryTransactionRepository();
        peerDebtUseCase = new PeerDebtService(peerDebtRepository, transactionRepository);
    }

    @Test
    void shouldRecordDirectDebtSuccessfully() {
        PeerDebtEntry entry = peerDebtUseCase.recordDirectDebt(
            "Alice",
            Money.of("75.00", "USD"),
            true,
            "Office lunch",
            LocalDate.of(2026, 9, 1)
        );

        assertThat(entry.id()).isNotBlank();
        assertThat(entry.contactName()).isEqualTo("Alice");
        assertThat(entry.amount()).isEqualTo(Money.of("75.00", "USD"));
        assertThat(entry.isLent()).isTrue();
        assertThat(entry.isSettled()).isFalse();

        Optional<PeerDebtEntry> saved = peerDebtRepository.findDebtById(entry.id());
        assertThat(saved).isPresent();
        assertThat(saved.get().description()).isEqualTo("Office lunch");
    }

    @Test
    void shouldMarkTransactionAs100PercentLentAndZeroOutPersonalExpense() {
        Transaction tx = new Transaction(
            new TransactionId("tx-100"),
            Money.of("120.00", "USD"),
            TransactionType.DEBIT,
            LocalDateTime.now(),
            "Apple Store",
            new AccountId("acc-1"),
            "SHOPPING",
            IngestionSource.MANUAL,
            ReconciliationStatus.CONFIRMED,
            Money.of("120.00", "USD")
        );
        transactionRepository.save(tx);

        Transaction updatedTx = peerDebtUseCase.markAs100PercentLent(tx.id(), "Bob");

        assertThat(updatedTx.netPersonalExpense()).isEqualTo(Money.zero("USD"));
        
        List<PeerDebtEntry> bobEntries = peerDebtRepository.findByContactName("Bob");
        assertThat(bobEntries).hasSize(1);
        PeerDebtEntry debt = bobEntries.get(0);
        assertThat(debt.amount()).isEqualTo(Money.of("120.00", "USD"));
        assertThat(debt.isLent()).isTrue();
        assertThat(debt.transactionId()).isEqualTo("tx-100");
    }

    @Test
    void shouldSplitTransactionAcrossMultipleContactsAndCalculateNetPersonalShare() {
        Transaction tx = new Transaction(
            new TransactionId("tx-split"),
            Money.of("150.00", "USD"),
            TransactionType.DEBIT,
            LocalDateTime.now(),
            "Dinner Bistro",
            new AccountId("acc-1"),
            "DINING",
            IngestionSource.MANUAL,
            ReconciliationStatus.CONFIRMED,
            Money.of("150.00", "USD")
        );
        transactionRepository.save(tx);

        List<ContactSplitRequest> splits = List.of(
            new ContactSplitRequest("Alice", Money.of("50.00", "USD"), "Alice share"),
            new ContactSplitRequest("Bob", Money.of("50.00", "USD"), "Bob share")
        );

        List<PeerDebtEntry> createdDebts = peerDebtUseCase.splitTransaction(tx.id(), splits);

        assertThat(createdDebts).hasSize(2);
        
        Transaction updatedTx = transactionRepository.findById(tx.id()).orElseThrow();
        assertThat(updatedTx.netPersonalExpense()).isEqualTo(Money.of("50.00", "USD"));

        assertThat(peerDebtRepository.findByContactName("Alice")).hasSize(1);
        assertThat(peerDebtRepository.findByContactName("Bob")).hasSize(1);
    }

    @Test
    void shouldRejectSplitIfTotalSplitExceedsTransactionAmount() {
        Transaction tx = new Transaction(
            new TransactionId("tx-split-invalid"),
            Money.of("100.00", "USD"),
            TransactionType.DEBIT,
            LocalDateTime.now(),
            "Dinner Bistro",
            new AccountId("acc-1"),
            "DINING",
            IngestionSource.MANUAL,
            ReconciliationStatus.CONFIRMED,
            Money.of("100.00", "USD")
        );
        transactionRepository.save(tx);

        List<ContactSplitRequest> splits = List.of(
            new ContactSplitRequest("Alice", Money.of("80.00", "USD"), "share 1"),
            new ContactSplitRequest("Bob", Money.of("40.00", "USD"), "share 2")
        );

        assertThatThrownBy(() -> peerDebtUseCase.splitTransaction(tx.id(), splits))
            .isInstanceOf(IllegalArgumentException.class)
            .hasMessageContaining("exceeds total transaction amount");
    }

    @Test
    void shouldSettleDebtPartiallyAndFully() {
        PeerDebtEntry entry = peerDebtUseCase.recordDirectDebt(
            "Charlie",
            Money.of("200.00", "USD"),
            true,
            "Rent advance",
            null
        );

        PeerDebtEntry partial = peerDebtUseCase.settleDebt(entry.id(), Money.of("100.00", "USD"));
        assertThat(partial.isSettled()).isFalse();
        assertThat(partial.remainingAmount()).isEqualTo(Money.of("100.00", "USD"));

        PeerDebtEntry full = peerDebtUseCase.settleDebt(entry.id(), Money.of("100.00", "USD"));
        assertThat(full.isSettled()).isTrue();
        assertThat(full.remainingAmount()).isEqualTo(Money.zero("USD"));
    }

    @Test
    void shouldAggregateContactDebtSummaries() {
        peerDebtUseCase.recordDirectDebt("Alice", Money.of("100.00", "USD"), true, "Lent", null);
        peerDebtUseCase.recordDirectDebt("Alice", Money.of("20.00", "USD"), false, "Borrowed", null);
        peerDebtUseCase.recordDirectDebt("Bob", Money.of("50.00", "USD"), false, "Borrowed for fuel", null);

        List<ContactDebtSummary> summaries = peerDebtUseCase.getAllContactSummaries();

        assertThat(summaries).hasSize(2);

        ContactDebtSummary aliceSummary = summaries.stream()
            .filter(s -> s.contactName().equals("Alice"))
            .findFirst()
            .orElseThrow();
        assertThat(aliceSummary.totalLent()).isEqualTo(Money.of("100.00", "USD"));
        assertThat(aliceSummary.totalBorrowed()).isEqualTo(Money.of("20.00", "USD"));
        assertThat(aliceSummary.netBalance()).isEqualTo(Money.of("80.00", "USD"));
        assertThat(aliceSummary.activeDebtCount()).isEqualTo(2);

        ContactDebtSummary bobSummary = summaries.stream()
            .filter(s -> s.contactName().equals("Bob"))
            .findFirst()
            .orElseThrow();
        assertThat(bobSummary.totalLent()).isEqualTo(Money.zero("USD"));
        assertThat(bobSummary.totalBorrowed()).isEqualTo(Money.of("50.00", "USD"));
        assertThat(bobSummary.netBalance()).isEqualTo(Money.of("-50.00", "USD"));
        assertThat(bobSummary.activeDebtCount()).isEqualTo(1);
    }

    private static class InMemoryPeerDebtRepository implements PeerDebtRepository {
        private final Map<String, PeerDebtEntry> store = new HashMap<>();

        @Override
        public void save(PeerDebtEntry debtEntry) {
            store.put(debtEntry.id(), debtEntry);
        }

        @Override
        public Optional<PeerDebtEntry> findDebtById(String id) {
            return Optional.ofNullable(store.get(id));
        }

        @Override
        public List<PeerDebtEntry> findByContactName(String contactName) {
            return store.values().stream()
                .filter(d -> d.contactName().equalsIgnoreCase(contactName))
                .toList();
        }

        @Override
        public List<PeerDebtEntry> findAllUnsettled() {
            return store.values().stream()
                .filter(d -> !d.isSettled())
                .toList();
        }

        @Override
        public List<PeerDebtEntry> findAllDebts() {
            return new ArrayList<>(store.values());
        }
    }
}
