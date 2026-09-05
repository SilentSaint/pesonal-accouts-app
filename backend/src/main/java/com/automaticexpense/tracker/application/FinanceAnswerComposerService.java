package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ComposeFinanceAnswerUseCase;
import com.automaticexpense.tracker.domain.FinanceAnswer;
import com.automaticexpense.tracker.domain.FinanceQueryPlan;
import com.automaticexpense.tracker.domain.IntelligenceResult;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.PeriodComparison;
import com.automaticexpense.tracker.domain.SpendingAnalytics;
import com.automaticexpense.tracker.domain.SpendingBreakdown;
import com.automaticexpense.tracker.domain.TransactionEvidence;

import java.util.List;
import java.util.stream.Collectors;

public final class FinanceAnswerComposerService implements ComposeFinanceAnswerUseCase {

    @Override
    public FinanceAnswer compose(
        FinanceQueryPlan plan,
        IntelligenceResult<SpendingAnalytics> result
    ) {
        String observation = switch (plan.capability()) {
            case SPENDING_TOTAL -> total(result.value());
            case MERCHANT_BREAKDOWN -> breakdown("merchant", result.value().merchantBreakdown());
            case CATEGORY_BREAKDOWN -> breakdown("category", result.value().categoryBreakdown());
            case LARGEST_PURCHASES -> largestPurchases(result.value().largestPurchases());
            case PERIOD_COMPARISON -> comparison(result.value().monthOverMonth(), result.value().currentPeriod().total());
            case EVIDENCE_DRILL_DOWN -> evidence(result.value().currentPeriod().transactionCount());
        };
        return new FinanceAnswer(
            result.classification(),
            observation,
            result.asOf(),
            result.formula(),
            result.evidence(),
            result.assumptions(),
            result.warnings()
        );
    }

    private String total(SpendingAnalytics analytics) {
        return "Personal spending for the selected period is "
            + money(analytics.currentPeriod().total()) + " across "
            + analytics.currentPeriod().transactionCount() + " canonical transactions.";
    }

    private String breakdown(String noun, List<SpendingBreakdown> breakdown) {
        if (breakdown.isEmpty()) {
            return "There are no canonical spending records for the selected period.";
        }
        SpendingBreakdown top = breakdown.getFirst();
        return "The highest spending " + noun + " is " + top.key() + " at "
            + money(top.total()) + " across " + top.transactionCount() + " canonical transactions.";
    }

    private String largestPurchases(List<TransactionEvidence> purchases) {
        if (purchases.isEmpty()) {
            return "There are no canonical purchases for the selected period.";
        }
        return "Largest canonical purchases: " + purchases.stream()
            .map(purchase -> purchase.merchantName() + " (" + money(purchase.personalSpend()) + ")")
            .collect(Collectors.joining(", ")) + ".";
    }

    private String comparison(PeriodComparison comparison, Money currentTotal) {
        String baseline = money(comparison.baseline().total());
        String current = money(currentTotal);
        if (comparison.percentageChange() == null) {
            return "Personal spending is " + current + " for the selected period versus "
                + baseline + " in the comparison period; no percentage is available because the baseline is zero.";
        }
        return "Personal spending is " + current + " for the selected period versus " + baseline
            + " in the comparison period, a " + comparison.percentageChange().toPlainString() + "% change.";
    }

    private String evidence(int sourceCount) {
        return "The calculation is supported by " + sourceCount
            + " canonical transactions. Open the evidence link to review the filtered records.";
    }

    private String money(Money amount) {
        return amount.currency() + " " + amount.amount().toPlainString();
    }
}
