package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.PeerDebtEntry;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;

import java.time.LocalDate;
import java.util.List;

public interface ManagePeerDebtUseCase {
    PeerDebtEntry recordDirectDebt(String contactName, Money amount, boolean isLent, String description, LocalDate dueDate);
    Transaction markAs100PercentLent(TransactionId transactionId, String contactName);
    List<PeerDebtEntry> splitTransaction(TransactionId transactionId, List<ContactSplitRequest> splits);
    PeerDebtEntry settleDebt(String debtId, Money settlementAmount);
    List<PeerDebtEntry> getLedgerForContact(String contactName);
    List<PeerDebtEntry> getUnsettledDebts();
    List<ContactDebtSummary> getAllContactSummaries();
}
