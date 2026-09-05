package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Objects;

public record ProactiveInsight(
    String id,
    ProactiveInsightType type,
    IntelligenceClassification classification,
    String title,
    String message,
    Money currentAmount,
    Money baselineAmount,
    String baselineLabel,
    BigDecimal confidence,
    Instant asOf,
    Instant freshnessAsOf,
    FormulaReference formula,
    EvidenceMetadata evidence,
    List<TransactionEvidence> matchingTransactions,
    List<String> assumptions,
    List<IntelligenceWarning> warnings,
    String deduplicationKey,
    Instant createdAt,
    Instant expiresAt,
    InsightLifecycleState lifecycleState
) {
    public ProactiveInsight {
        if (id == null || id.isBlank()) throw new IllegalArgumentException("id cannot be blank");
        Objects.requireNonNull(type, "type cannot be null");
        if (classification != IntelligenceClassification.DERIVED_INSIGHT) {
            throw new IllegalArgumentException("proactive insights must be classified as derived insights");
        }
        if (title == null || title.isBlank() || message == null || message.isBlank()) {
            throw new IllegalArgumentException("title and message cannot be blank");
        }
        Objects.requireNonNull(currentAmount, "currentAmount cannot be null");
        Objects.requireNonNull(baselineAmount, "baselineAmount cannot be null");
        if (!currentAmount.currency().equals(baselineAmount.currency())) {
            throw new IllegalArgumentException("currentAmount and baselineAmount must use the same currency");
        }
        if (baselineLabel == null || baselineLabel.isBlank()) {
            throw new IllegalArgumentException("baselineLabel cannot be blank");
        }
        Objects.requireNonNull(confidence, "confidence cannot be null");
        if (confidence.compareTo(BigDecimal.ZERO) < 0 || confidence.compareTo(BigDecimal.ONE) > 0) {
            throw new IllegalArgumentException("confidence must be between zero and one");
        }
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(freshnessAsOf, "freshnessAsOf cannot be null");
        Objects.requireNonNull(formula, "formula cannot be null");
        Objects.requireNonNull(evidence, "evidence cannot be null");
        matchingTransactions = List.copyOf(matchingTransactions == null ? List.of() : matchingTransactions);
        assumptions = List.copyOf(assumptions == null ? List.of() : assumptions);
        warnings = List.copyOf(warnings == null ? List.of() : warnings);
        if (deduplicationKey == null || deduplicationKey.isBlank()) {
            throw new IllegalArgumentException("deduplicationKey cannot be blank");
        }
        Objects.requireNonNull(createdAt, "createdAt cannot be null");
        Objects.requireNonNull(expiresAt, "expiresAt cannot be null");
        if (!expiresAt.isAfter(createdAt)) throw new IllegalArgumentException("expiresAt must be after createdAt");
        Objects.requireNonNull(lifecycleState, "lifecycleState cannot be null");
    }

    public boolean isCurrentAt(Instant instant) {
        return lifecycleState == InsightLifecycleState.ACTIVE && expiresAt.isAfter(instant);
    }

    public ProactiveInsight dismissed() {
        return new ProactiveInsight(
            id, type, classification, title, message, currentAmount, baselineAmount, baselineLabel,
            confidence, asOf, freshnessAsOf, formula, evidence, matchingTransactions, assumptions, warnings,
            deduplicationKey, createdAt, expiresAt, InsightLifecycleState.DISMISSED
        );
    }
}
