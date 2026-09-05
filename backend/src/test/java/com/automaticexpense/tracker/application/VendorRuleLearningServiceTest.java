package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IngestionSource;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.TransactionType;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class VendorRuleLearningServiceTest {

    @Test
    void confirmsTheCorrectionAndPersistsItsNormalizedCategoryAndSubcategoryRule() {
        InMemoryTransactionRepository transactions = new InMemoryTransactionRepository();
        InMemoryVendorRuleRepository rules = new InMemoryVendorRuleRepository();
        Transaction transaction = transaction("Saira Banu");
        transactions.save(transaction);
        VendorRuleLearningService service = new VendorRuleLearningService(transactions, rules);

        Transaction confirmed = service.learn(
            transaction.id(), "Food & Dining", "Tea & Snacks", "Saira's tea stall"
        );

        assertThat(confirmed.reconciliationStatus()).isEqualTo(ReconciliationStatus.CONFIRMED);
        assertThat(confirmed.categoryId()).isEqualTo("Food & Dining");
        assertThat(confirmed.subCategory()).isEqualTo("Tea & Snacks");
        assertThat(rules.findByPayeeKey("saira banu"))
            .hasValueSatisfying(rule -> {
                assertThat(rule.categoryId()).isEqualTo("Food & Dining");
                assertThat(rule.subCategory()).isEqualTo("Tea & Snacks");
                assertThat(rule.payeeNickname()).isEqualTo("Saira's tea stall");
            });
    }

    private Transaction transaction(String merchant) {
        return new Transaction(
            new TransactionId("txn-vendor-rule-001"),
            Money.of("150.00", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 8, 29, 10, 0),
            merchant,
            new AccountId("acc-7788"),
            null,
            IngestionSource.SMS,
            ReconciliationStatus.NEEDS_REVIEW,
            Money.of("150.00", "INR")
        );
    }
}
