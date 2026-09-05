package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.BillStatement;
import com.automaticexpense.tracker.domain.Money;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface BillRepository {
    void save(BillStatement billStatement);
    Optional<BillStatement> findBillById(String billId);
    List<BillStatement> findPendingBills();
    List<BillStatement> findAllBills();

    default Optional<BillStatement> findByAccountIdAndStatementDate(
        String accountId,
        LocalDate statementDate
    ) {
        return findAllBills().stream()
            .filter(bill -> bill.accountId().value().equals(accountId))
            .filter(bill -> bill.statementDate().equals(statementDate))
            .findFirst();
    }

    default Optional<BillStatement> recordPaymentAtomically(
        String billId,
        String paymentTransactionId,
        Money paymentAmount
    ) {
        return findBillById(billId).map(bill -> {
            if (bill.recordPayment(paymentTransactionId, paymentAmount)) {
                save(bill);
            }
            return bill;
        });
    }
}
