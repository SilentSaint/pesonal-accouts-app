package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.ExpectedAmountRange;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.RecurringCommitment;
import com.automaticexpense.tracker.domain.RecurringCommitmentCadence;
import com.automaticexpense.tracker.domain.RecurringCommitmentClassification;
import com.automaticexpense.tracker.domain.RecurringCommitmentOrigin;
import com.automaticexpense.tracker.domain.RecurringCommitmentState;
import com.automaticexpense.tracker.domain.RecurringCommitmentStatus;
import com.automaticexpense.tracker.domain.TransactionId;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

final class RecurringCommitmentDynamoDbMapper {
    private RecurringCommitmentDynamoDbMapper() {}

    static Map<String, String> from(String userId, RecurringCommitment commitment) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "RECUR#" + commitment.id());
        item.put("entityType", "RECURRING_COMMITMENT");
        item.put("commitmentId", commitment.id());
        item.put("name", commitment.name());
        item.put("commitmentClassification", commitment.classification().name());
        item.put("cadence", commitment.cadence().name());
        item.put("minimumAmount", commitment.expectedAmountRange().minimum().amount().toPlainString());
        item.put("maximumAmount", commitment.expectedAmountRange().maximum().amount().toPlainString());
        item.put("currency", commitment.expectedAmountRange().minimum().currency());
        item.put("nextPaymentDate", commitment.nextPaymentDate().toString());
        item.put("confidence", Double.toString(commitment.confidence()));
        item.put("supportingTransactionIds", commitment.supportingTransactionIds().stream()
            .map(TransactionId::value).sorted().collect(Collectors.joining(",")));
        item.put("commitmentStatus", commitment.status().name());
        item.put("commitmentState", commitment.state().name());
        item.put("commitmentOrigin", commitment.origin().name());
        putIfPresent(item, "authoritativeReference", commitment.authoritativeReference());
        putIfPresent(item, "candidateKey", commitment.candidateKey());
        return item;
    }

    static RecurringCommitment to(Map<String, String> item) {
        Set<TransactionId> evidence = item.containsKey("supportingTransactionIds")
            && !item.get("supportingTransactionIds").isBlank()
            ? java.util.Arrays.stream(item.get("supportingTransactionIds").split(","))
                .map(TransactionId::new).collect(Collectors.toSet())
            : Set.of();
        String currency = item.get("currency");
        return new RecurringCommitment(
            item.get("commitmentId"), item.get("name"),
            RecurringCommitmentClassification.valueOf(item.get("commitmentClassification")),
            RecurringCommitmentCadence.valueOf(item.get("cadence")),
            new ExpectedAmountRange(
                Money.of(new BigDecimal(item.get("minimumAmount")), currency),
                Money.of(new BigDecimal(item.get("maximumAmount")), currency)
            ),
            java.time.LocalDate.parse(item.get("nextPaymentDate")), Double.parseDouble(item.get("confidence")),
            evidence, RecurringCommitmentStatus.valueOf(item.get("commitmentStatus")),
            RecurringCommitmentState.valueOf(item.get("commitmentState")),
            RecurringCommitmentOrigin.valueOf(item.get("commitmentOrigin")),
            item.get("authoritativeReference"), item.get("candidateKey")
        );
    }

    private static void putIfPresent(Map<String, String> item, String field, String value) {
        if (value != null) item.put(field, value);
    }
}
