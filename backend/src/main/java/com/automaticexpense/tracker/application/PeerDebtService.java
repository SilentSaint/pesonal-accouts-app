package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ContactDebtSummary;
import com.automaticexpense.tracker.application.port.in.ContactSplitRequest;
import com.automaticexpense.tracker.application.port.in.ManagePeerDebtUseCase;
import com.automaticexpense.tracker.application.port.out.PeerDebtRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.PeerDebtEntry;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

public class PeerDebtService implements ManagePeerDebtUseCase {

    private final PeerDebtRepository peerDebtRepository;
    private final TransactionRepository transactionRepository;

    public PeerDebtService(PeerDebtRepository peerDebtRepository, TransactionRepository transactionRepository) {
        this.peerDebtRepository = Objects.requireNonNull(peerDebtRepository, "peerDebtRepository cannot be null");
        this.transactionRepository = Objects.requireNonNull(transactionRepository, "transactionRepository cannot be null");
    }

    @Override
    public PeerDebtEntry recordDirectDebt(String contactName, Money amount, boolean isLent, String description, LocalDate dueDate) {
        Objects.requireNonNull(contactName, "contactName cannot be null");
        Objects.requireNonNull(amount, "amount cannot be null");

        PeerDebtEntry entry = new PeerDebtEntry(
            UUID.randomUUID().toString(),
            contactName,
            amount,
            Money.zero(amount.currency()),
            description != null ? description : "",
            isLent,
            false,
            null,
            LocalDateTime.now(),
            dueDate
        );

        peerDebtRepository.save(entry);
        return entry;
    }

    @Override
    public Transaction markAs100PercentLent(TransactionId transactionId, String contactName) {
        Objects.requireNonNull(transactionId, "transactionId cannot be null");
        Objects.requireNonNull(contactName, "contactName cannot be null");

        Transaction tx = transactionRepository.findById(transactionId)
            .orElseThrow(() -> new IllegalArgumentException("Transaction not found: " + transactionId.value()));

        tx.setNetPersonalExpense(Money.zero(tx.amount().currency()));
        transactionRepository.save(tx);

        PeerDebtEntry debt = new PeerDebtEntry(
            UUID.randomUUID().toString(),
            contactName,
            tx.amount(),
            Money.zero(tx.amount().currency()),
            "100% Lent for transaction: " + tx.merchantName(),
            true,
            false,
            tx.id().value(),
            LocalDateTime.now(),
            null
        );

        peerDebtRepository.save(debt);
        return tx;
    }

    @Override
    public List<PeerDebtEntry> splitTransaction(TransactionId transactionId, List<ContactSplitRequest> splits) {
        Objects.requireNonNull(transactionId, "transactionId cannot be null");
        Objects.requireNonNull(splits, "splits cannot be null");

        if (splits.isEmpty()) {
            throw new IllegalArgumentException("Splits list cannot be empty");
        }

        Transaction tx = transactionRepository.findById(transactionId)
            .orElseThrow(() -> new IllegalArgumentException("Transaction not found: " + transactionId.value()));

        String currency = tx.amount().currency();
        Money totalSplitAmount = Money.zero(currency);

        for (ContactSplitRequest split : splits) {
            totalSplitAmount = totalSplitAmount.add(split.shareAmount());
        }

        if (totalSplitAmount.isGreaterThan(tx.amount())) {
            throw new IllegalArgumentException("Total split amount " + totalSplitAmount + " exceeds total transaction amount " + tx.amount());
        }

        Money personalShare = tx.amount().subtract(totalSplitAmount);
        tx.setNetPersonalExpense(personalShare);
        transactionRepository.save(tx);

        List<PeerDebtEntry> createdEntries = new ArrayList<>();
        for (ContactSplitRequest split : splits) {
            PeerDebtEntry entry = new PeerDebtEntry(
                UUID.randomUUID().toString(),
                split.contactName(),
                split.shareAmount(),
                Money.zero(currency),
                split.note() != null ? split.note() : ("Split share for: " + tx.merchantName()),
                true,
                false,
                tx.id().value(),
                LocalDateTime.now(),
                null
            );
            peerDebtRepository.save(entry);
            createdEntries.add(entry);
        }

        return createdEntries;
    }

    @Override
    public PeerDebtEntry settleDebt(String debtId, Money settlementAmount) {
        Objects.requireNonNull(debtId, "debtId cannot be null");
        Objects.requireNonNull(settlementAmount, "settlementAmount cannot be null");

        PeerDebtEntry debt = peerDebtRepository.findDebtById(debtId)
            .orElseThrow(() -> new IllegalArgumentException("Peer debt entry not found: " + debtId));

        debt.partiallySettle(settlementAmount);
        peerDebtRepository.save(debt);
        return debt;
    }

    @Override
    public List<PeerDebtEntry> getLedgerForContact(String contactName) {
        Objects.requireNonNull(contactName, "contactName cannot be null");
        return peerDebtRepository.findByContactName(contactName);
    }

    @Override
    public List<PeerDebtEntry> getUnsettledDebts() {
        return peerDebtRepository.findAllUnsettled();
    }

    @Override
    public List<ContactDebtSummary> getAllContactSummaries() {
        List<PeerDebtEntry> all = peerDebtRepository.findAllDebts();
        Map<String, List<PeerDebtEntry>> byContact = all.stream()
            .collect(Collectors.groupingBy(PeerDebtEntry::contactName));

        List<ContactDebtSummary> summaries = new ArrayList<>();

        for (Map.Entry<String, List<PeerDebtEntry>> entry : byContact.entrySet()) {
            String contactName = entry.getKey();
            List<PeerDebtEntry> entries = entry.getValue();

            String currency = entries.isEmpty() ? "USD" : entries.get(0).amount().currency();
            Money totalLent = Money.zero(currency);
            Money totalBorrowed = Money.zero(currency);
            int activeCount = 0;

            for (PeerDebtEntry d : entries) {
                if (!d.isSettled()) {
                    activeCount++;
                    if (d.isLent()) {
                        totalLent = totalLent.add(d.remainingAmount());
                    } else {
                        totalBorrowed = totalBorrowed.add(d.remainingAmount());
                    }
                }
            }

            Money netBalance = totalLent.subtract(totalBorrowed);
            summaries.add(new ContactDebtSummary(
                contactName,
                netBalance,
                totalLent,
                totalBorrowed,
                activeCount
            ));
        }

        return summaries;
    }
}
