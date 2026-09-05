package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.BillStatement;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.Transaction;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface ReconcileBillUseCase {
    BillStatement registerBill(
        AccountId accountId,
        String cardName,
        Money totalAmount,
        Money minimumDue,
        LocalDate statementDate,
        LocalDate dueDate
    );

    BillStatement recordBillPayment(String billId, Money paymentAmount);

    Optional<BillStatement> autoMatchBillPaymentDebit(Transaction debitTx);

    List<BillStatement> getUpcomingBills();

    List<BillStatement> getAllBills();
}
