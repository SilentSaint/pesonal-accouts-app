package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.FinancialAccount;
import com.automaticexpense.tracker.domain.Transaction;

/**
 * Persistence operations which must update the canonical transaction and review state together.
 */
public interface CanonicalTransactionRepository extends TransactionRepository {
    boolean mergeCanonically(Transaction canonical, Transaction duplicate);

    boolean confirmAsSeparate(FinancialAccount account, Transaction transaction);
}
