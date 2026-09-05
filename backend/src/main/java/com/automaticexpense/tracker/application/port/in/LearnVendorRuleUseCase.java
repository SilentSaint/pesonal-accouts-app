package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;

/**
 * Confirms a reviewed transaction and remembers its category for the payee.
 */
public interface LearnVendorRuleUseCase {
    Transaction learn(
        TransactionId transactionId,
        String categoryId,
        String subCategory,
        String payeeNickname
    );
}
