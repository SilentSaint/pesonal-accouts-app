package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.FinancialAccount;
import com.automaticexpense.tracker.domain.Transaction;

public interface AccountTransactionRepository extends AccountRepository, TransactionRepository {
    boolean saveAtomically(FinancialAccount account, Transaction transaction);
}
