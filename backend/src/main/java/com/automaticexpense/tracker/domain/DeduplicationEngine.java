package com.automaticexpense.tracker.domain;

import java.time.Duration;
import java.util.List;

public class DeduplicationEngine {

    private static final long WINDOW_MINUTES = 15;

    public DeduplicationResult evaluate(ParsedTransactionEvent candidate, IngestionSource candidateSource, List<Transaction> existingTransactionsInWindow) {
        if (existingTransactionsInWindow == null || existingTransactionsInWindow.isEmpty()) {
            return DeduplicationResult.createNew(ReconciliationStatus.CONFIRMED);
        }

        for (Transaction existing : existingTransactionsInWindow) {
            if (existing.potentialDuplicateOfTransactionId() != null) {
                continue;
            }
            if (existing.ingestionSources().contains(candidateSource)) {
                if (existing.ingestionSources().size() > 1
                    && existing.amount().amount().compareTo(candidate.amount()) == 0
                    && existing.type() == candidate.type()
                    && isExactOrCompatibleMerchant(existing.merchantName(), candidate.merchantName())) {
                    return DeduplicationResult.autoMerge(existing.id());
                }
                continue;
            }
            if (existing.amount().amount().compareTo(candidate.amount()) == 0 &&
                existing.type() == candidate.type()) {
                
                long minutesDiff = Math.abs(Duration.between(existing.timestamp(), candidate.timestamp()).toMinutes());
                if (minutesDiff <= WINDOW_MINUTES) {
                    if (isExactOrCompatibleMerchant(existing.merchantName(), candidate.merchantName())) {
                        return DeduplicationResult.autoMerge(existing.id());
                    } else {
                        return DeduplicationResult.flagNeedsReview(existing.id());
                    }
                }
            }
        }

        return DeduplicationResult.createNew(ReconciliationStatus.CONFIRMED);
    }

    private boolean isExactOrCompatibleMerchant(String m1, String m2) {
        if (m1 == null || m2 == null) return false;
        String norm1 = m1.trim().toLowerCase();
        String norm2 = m2.trim().toLowerCase();
        return norm1.equals(norm2) || norm1.contains(norm2) || norm2.contains(norm1);
    }
}
