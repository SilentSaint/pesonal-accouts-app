package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.LearnVendorRuleUseCase;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.application.port.out.VendorRuleRepository;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.VendorCategoryRule;

import java.util.Objects;

public final class VendorRuleLearningService implements LearnVendorRuleUseCase {
    private final TransactionRepository transactions;
    private final VendorRuleRepository rules;

    public VendorRuleLearningService(TransactionRepository transactions, VendorRuleRepository rules) {
        this.transactions = Objects.requireNonNull(transactions, "transactions cannot be null");
        this.rules = Objects.requireNonNull(rules, "rules cannot be null");
    }

    @Override
    public Transaction learn(
        TransactionId transactionId,
        String categoryId,
        String subCategory,
        String payeeNickname
    ) {
        Transaction existing = transactions.findById(Objects.requireNonNull(transactionId, "transactionId cannot be null"))
            .orElseThrow(() -> new IllegalArgumentException("Transaction not found: " + transactionId.value()));
        VendorCategoryRule rule = VendorCategoryRule.fromCorrection(
            existing.merchantName(), categoryId, subCategory, payeeNickname
        );
        Transaction confirmed = existing.confirmedWithCategory(rule.categoryId(), rule.subCategory());
        transactions.save(confirmed);
        rules.save(rule);
        return confirmed;
    }
}
