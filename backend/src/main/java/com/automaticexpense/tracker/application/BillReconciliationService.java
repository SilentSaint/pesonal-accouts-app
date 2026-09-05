package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ReconcileBillUseCase;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.BillStatement;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionType;

import java.time.LocalDate;
import java.util.*;

public class BillReconciliationService implements ReconcileBillUseCase {

    private final BillRepository billRepository;

    public BillReconciliationService(BillRepository billRepository) {
        this.billRepository = Objects.requireNonNull(billRepository, "billRepository cannot be null");
    }

    @Override
    public BillStatement registerBill(
        AccountId accountId,
        String cardName,
        Money totalAmount,
        Money minimumDue,
        LocalDate statementDate,
        LocalDate dueDate
    ) {
        Objects.requireNonNull(accountId, "accountId cannot be null");
        Objects.requireNonNull(totalAmount, "totalAmount cannot be null");
        Objects.requireNonNull(minimumDue, "minimumDue cannot be null");
        Objects.requireNonNull(dueDate, "dueDate cannot be null");

        BillStatement bill = new BillStatement(
            UUID.randomUUID().toString(),
            accountId,
            cardName,
            totalAmount,
            minimumDue,
            statementDate,
            dueDate
        );

        billRepository.save(bill);
        return bill;
    }

    @Override
    public BillStatement recordBillPayment(String billId, Money paymentAmount) {
        Objects.requireNonNull(billId, "billId cannot be null");
        Objects.requireNonNull(paymentAmount, "paymentAmount cannot be null");

        BillStatement bill = billRepository.findBillById(billId)
            .orElseThrow(() -> new IllegalArgumentException("Bill statement not found: " + billId));

        return billRepository.recordPaymentAtomically(
                billId, "manual-" + UUID.randomUUID(), paymentAmount
            )
            .orElseThrow(() -> new IllegalArgumentException("Bill statement not found: " + billId));
    }

    @Override
    public Optional<BillStatement> autoMatchBillPaymentDebit(Transaction debitTx) {
        if (debitTx == null || debitTx.type() != TransactionType.DEBIT) {
            return Optional.empty();
        }

        List<BillStatement> pendingBills = billRepository.findPendingBills();
        String merchant = debitTx.merchantName().toLowerCase(Locale.ROOT);

        for (BillStatement bill : pendingBills) {
            boolean matchesCardName = matchesCardIssuer(merchant, bill.cardName());

            boolean matchesAmount = bill.totalAmount().currency().equalsIgnoreCase(debitTx.amount().currency())
                && (bill.totalAmount().amount().compareTo(debitTx.amount().amount()) == 0
                || bill.remainingDue().amount().compareTo(debitTx.amount().amount()) == 0);

            if (matchesCardName && matchesAmount) {
                return billRepository.recordPaymentAtomically(
                    bill.id(), debitTx.id().value(), debitTx.amount()
                );
            }
        }

        return Optional.empty();
    }

    @Override
    public List<BillStatement> getUpcomingBills() {
        return billRepository.findPendingBills();
    }

    @Override
    public List<BillStatement> getAllBills() {
        return billRepository.findAllBills();
    }

    private boolean matchesCardIssuer(String merchant, String cardName) {
        return Arrays.stream(cardName.toLowerCase(Locale.ROOT).split("\\s+"))
            .filter(token -> token.length() > 2)
            .filter(token -> !Set.of("credit", "card", "bank", "payment").contains(token))
            .anyMatch(merchant::contains);
    }
}
