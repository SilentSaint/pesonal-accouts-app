package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.ReconciliationReview;

import java.util.List;

public interface ReconciliationReviewUseCase {
    List<Transaction> getPendingReviewTransactions();

    List<ReconciliationReview> getPendingReconciliationReviews();

    Transaction confirmTransaction(TransactionId id, String categoryId);

    Transaction mergeTransactions(TransactionId canonicalTransactionId, TransactionId duplicateTransactionId);
}
