package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Function;

public final class ProactiveInsightCalculator {
    public static final FormulaReference FORMULA = new FormulaReference("proactive-spending-insights", "1.0.0");
    private static final String BASELINE_LABEL = "three comparable prior months";

    public List<ProactiveInsight> evaluate(FinancialSnapshot snapshot, ProactiveInsightRequest request) {
        List<Transaction> canonicalDebits = canonicalDebits(snapshot, request.currency());
        if (canonicalDebits.isEmpty()) return List.of();
        YearMonth month = YearMonth.from(localDate(snapshot.asOf(), snapshot.timezone()));
        List<ProactiveInsight> insights = new ArrayList<>();
        addPeriodInsight(insights, ProactiveInsightType.SPENDING_SPIKE, "all spending", canonicalDebits,
            transaction -> "ALL", month, snapshot, request);
        addPeriodInsight(insights, ProactiveInsightType.SPENDING_REDUCTION, "all spending", canonicalDebits,
            transaction -> "ALL", month, snapshot, request);
        addGroupedInsights(insights, ProactiveInsightType.CATEGORY_INCREASE, "category", canonicalDebits,
            transaction -> transaction.categoryId() == null ? "UNCATEGORIZED" : transaction.categoryId(),
            month, snapshot, request);
        addGroupedInsights(insights, ProactiveInsightType.MERCHANT_INCREASE, "merchant", canonicalDebits,
            Transaction::merchantName, month, snapshot, request);
        addWeekendInsight(insights, canonicalDebits, month, snapshot, request);
        addUnusualPurchaseInsights(insights, canonicalDebits, month, snapshot, request);
        return List.copyOf(insights);
    }

    private void addPeriodInsight(
        List<ProactiveInsight> insights, ProactiveInsightType type, String label, List<Transaction> transactions,
        Function<Transaction, String> key, YearMonth month, FinancialSnapshot snapshot, ProactiveInsightRequest request
    ) {
        List<Money> historical = historicalTotals(
            transactions, key, "ALL", month, snapshot.asOf(), snapshot.timezone(), request
        );
        List<Transaction> current = inMonth(transactions, month, snapshot.timezone());
        Money currentTotal = total(current, request.currency());
        if (!hasHistory(historical, request)) return;
        Money baseline = average(historical, request.currency());
        if (type == ProactiveInsightType.SPENDING_SPIKE && significantIncrease(currentTotal, baseline, request)) {
            insights.add(insight(type, label, currentTotal, baseline, current, month, snapshot, request));
        }
        if (type == ProactiveInsightType.SPENDING_REDUCTION && significantReduction(currentTotal, baseline, request)) {
            insights.add(insight(type, label, currentTotal, baseline, current, month, snapshot, request));
        }
    }

    private void addGroupedInsights(
        List<ProactiveInsight> insights, ProactiveInsightType type, String noun, List<Transaction> transactions,
        Function<Transaction, String> key, YearMonth month, FinancialSnapshot snapshot, ProactiveInsightRequest request
    ) {
        Map<String, List<Transaction>> groups = groupBy(transactions, key);
        for (Map.Entry<String, List<Transaction>> entry : groups.entrySet()) {
            List<Money> historical = historicalTotals(
                entry.getValue(), key, entry.getKey(), month, snapshot.asOf(), snapshot.timezone(), request
            );
            List<Transaction> current = inMonth(entry.getValue(), month, snapshot.timezone());
            Money currentTotal = total(current, request.currency());
            if (hasHistory(historical, request) && significantIncrease(currentTotal, average(historical, request.currency()), request)) {
                insights.add(insight(type, noun + " " + entry.getKey(), currentTotal,
                    average(historical, request.currency()), current, month, snapshot, request));
            }
        }
    }

    private void addWeekendInsight(
        List<ProactiveInsight> insights, List<Transaction> transactions, YearMonth month,
        FinancialSnapshot snapshot, ProactiveInsightRequest request
    ) {
        List<Transaction> weekend = transactions.stream()
            .filter(transaction -> isWeekend(localDate(transaction.timestamp(), snapshot.timezone())))
            .toList();
        List<Money> historical = historicalTotals(
            weekend, transaction -> "WEEKEND", "WEEKEND", month, snapshot.asOf(), snapshot.timezone(), request
        );
        List<Transaction> current = inMonth(weekend, month, snapshot.timezone());
        Money currentTotal = total(current, request.currency());
        if (hasHistory(historical, request) && significantIncrease(currentTotal, average(historical, request.currency()), request)) {
            insights.add(insight(ProactiveInsightType.WEEKEND_SPENDING_CHANGE, "weekend spending", currentTotal,
                average(historical, request.currency()), current, month, snapshot, request));
        }
    }

    private void addUnusualPurchaseInsights(
        List<ProactiveInsight> insights, List<Transaction> transactions, YearMonth month,
        FinancialSnapshot snapshot, ProactiveInsightRequest request
    ) {
        for (Transaction current : inMonth(transactions, month, snapshot.timezone())) {
            List<Money> previousAmounts = transactions.stream()
                .filter(transaction -> sameCategory(transaction, current))
                .filter(transaction -> localDate(transaction.timestamp(), snapshot.timezone()).isBefore(month.atDay(1)))
                .map(Transaction::netPersonalExpense)
                .sorted(Comparator.comparing(Money::amount))
                .toList();
            if (previousAmounts.size() < request.minimumComparablePeriods()) continue;
            Money median = previousAmounts.get(previousAmounts.size() / 2);
            Money threshold = new Money(median.amount().multiply(BigDecimal.valueOf(3)), request.currency());
            if (current.netPersonalExpense().compareTo(threshold) >= 0
                && current.netPersonalExpense().subtract(median).compareTo(request.minimumAbsoluteChange()) >= 0) {
                insights.add(insight(ProactiveInsightType.UNUSUAL_PURCHASE,
                    "a " + categoryName(current) + " purchase", current.netPersonalExpense(), median,
                    List.of(current), month, snapshot, request));
            }
        }
    }

    private ProactiveInsight insight(
        ProactiveInsightType type, String subject, Money current, Money baseline, List<Transaction> matching,
        YearMonth month, FinancialSnapshot snapshot, ProactiveInsightRequest request
    ) {
        String key = type + ":" + normalizedSubject(subject) + ":" + month;
        BigDecimal change = current.amount().subtract(baseline.amount()).abs();
        BigDecimal ratio = baseline.amount().signum() == 0 ? BigDecimal.ONE
            : change.divide(baseline.amount(), 2, RoundingMode.HALF_UP).min(BigDecimal.ONE);
        BigDecimal confidence = BigDecimal.valueOf(0.60).add(ratio.multiply(BigDecimal.valueOf(0.30)))
            .add(BigDecimal.valueOf(0.10)).min(BigDecimal.ONE).setScale(2, RoundingMode.HALF_UP);
        Instant expiresAt = month.plusMonths(2).atDay(1).atStartOfDay(snapshot.timezone()).toInstant();
        List<TransactionEvidence> evidence = matching.stream().map(this::evidence).toList();
        String direction = type == ProactiveInsightType.SPENDING_REDUCTION ? "lower" : "higher";
        String title = title(type, subject);
        return new ProactiveInsight(
            hash(key), type, IntelligenceClassification.DERIVED_INSIGHT, title,
            subject + " is " + formatPercentage(current, baseline) + "% " + direction
                + " than your " + BASELINE_LABEL + ".",
            current, baseline, BASELINE_LABEL, confidence, snapshot.asOf(), snapshot.asOf(), FORMULA,
            new EvidenceMetadata(evidence.size(), drillDown(month, request.currency(), type, subject)),
            evidence,
            List.of("Only canonical personal debit transactions are included.",
                "The current month is compared with the same calendar-month unit in each prior month.",
                "An insight requires at least " + request.minimumComparablePeriods() + " comparable periods."),
            List.of(), key, snapshot.asOf(), expiresAt, InsightLifecycleState.ACTIVE
        );
    }

    private DrillDownReference drillDown(YearMonth month, String currency, ProactiveInsightType type, String subject) {
        String category = type == ProactiveInsightType.CATEGORY_INCREASE
            ? subject.substring("category ".length()) : null;
        String merchant = type == ProactiveInsightType.MERCHANT_INCREASE
            ? subject.substring("merchant ".length()) : null;
        return new DrillDownReference(new DateRange(month.atDay(1), month.atEndOfMonth()), currency,
            java.util.Set.of(), category, merchant);
    }

    private List<Transaction> canonicalDebits(FinancialSnapshot snapshot, String currency) {
        return snapshot.canonicalTransactions().stream()
            .filter(transaction -> transaction.type() == TransactionType.DEBIT)
            .filter(transaction -> transaction.reconciliationStatus() == ReconciliationStatus.CONFIRMED
                || transaction.reconciliationStatus() == ReconciliationStatus.AUTO_MERGED)
            .filter(transaction -> transaction.transferCounterpartMask() == null || transaction.transferCounterpartMask().isBlank())
            .filter(transaction -> currency.equals(transaction.amount().currency()))
            .filter(transaction -> !transaction.timestamp().toInstant(ZoneOffset.UTC).isAfter(snapshot.asOf()))
            .toList();
    }

    private List<Money> historicalTotals(
        List<Transaction> transactions, Function<Transaction, String> key, String expectedKey, YearMonth month,
        Instant asOf, ZoneId timezone, ProactiveInsightRequest request
    ) {
        List<Money> totals = new ArrayList<>();
        for (int offset = 1; offset <= request.minimumComparablePeriods(); offset++) {
            YearMonth prior = month.minusMonths(offset);
            LocalDate endingDay = prior.atDay(Math.min(
                localDate(asOf, timezone).getDayOfMonth(), prior.lengthOfMonth()
            ));
            List<Transaction> matching = inMonth(transactions, prior, timezone).stream()
                .filter(transaction -> !localDate(transaction.timestamp(), timezone).isAfter(endingDay))
                .filter(transaction -> expectedKey.equals(key.apply(transaction))).toList();
            if (matching.isEmpty()) return List.of();
            totals.add(total(matching, request.currency()));
        }
        return totals;
    }

    private boolean hasHistory(List<Money> historical, ProactiveInsightRequest request) {
        return historical.size() == request.minimumComparablePeriods()
            && historical.stream().allMatch(amount -> amount.amount().signum() > 0);
    }

    private boolean significantIncrease(Money current, Money baseline, ProactiveInsightRequest request) {
        if (baseline.amount().signum() == 0) return false;
        Money change = current.subtract(baseline);
        return change.compareTo(request.minimumAbsoluteChange()) >= 0
            && change.amount().divide(baseline.amount(), 4, RoundingMode.HALF_UP)
                .compareTo(request.relativeChangeThreshold()) >= 0;
    }

    private boolean significantReduction(Money current, Money baseline, ProactiveInsightRequest request) {
        if (baseline.amount().signum() == 0) return false;
        Money reduction = baseline.subtract(current);
        return reduction.compareTo(request.minimumAbsoluteChange()) >= 0
            && reduction.amount().divide(baseline.amount(), 4, RoundingMode.HALF_UP)
                .compareTo(request.relativeChangeThreshold()) >= 0;
    }

    private Map<String, List<Transaction>> groupBy(List<Transaction> transactions, Function<Transaction, String> key) {
        Map<String, List<Transaction>> groups = new LinkedHashMap<>();
        for (Transaction transaction : transactions) {
            groups.computeIfAbsent(key.apply(transaction), ignored -> new ArrayList<>()).add(transaction);
        }
        return groups;
    }

    private List<Transaction> inMonth(List<Transaction> transactions, YearMonth month, ZoneId timezone) {
        return transactions.stream().filter(transaction -> month.equals(YearMonth.from(localDate(transaction.timestamp(), timezone)))).toList();
    }

    private Money total(List<Transaction> transactions, String currency) {
        return transactions.stream().map(Transaction::netPersonalExpense).reduce(Money.zero(currency), Money::add);
    }

    private Money average(List<Money> amounts, String currency) {
        BigDecimal sum = amounts.stream().map(Money::amount).reduce(BigDecimal.ZERO, BigDecimal::add);
        return new Money(sum.divide(BigDecimal.valueOf(amounts.size()), 2, RoundingMode.HALF_UP), currency);
    }

    private TransactionEvidence evidence(Transaction transaction) {
        return new TransactionEvidence(transaction.id().value(), transaction.timestamp(), transaction.merchantName(),
            transaction.netPersonalExpense());
    }

    private boolean sameCategory(Transaction first, Transaction second) {
        return categoryName(first).equals(categoryName(second));
    }

    private String categoryName(Transaction transaction) {
        return transaction.categoryId() == null ? "UNCATEGORIZED" : transaction.categoryId();
    }

    private boolean isWeekend(LocalDate date) {
        return date.getDayOfWeek() == DayOfWeek.SATURDAY || date.getDayOfWeek() == DayOfWeek.SUNDAY;
    }

    private LocalDate localDate(Instant instant, ZoneId timezone) {
        return instant.atZone(timezone).toLocalDate();
    }

    private LocalDate localDate(java.time.LocalDateTime timestamp, ZoneId timezone) {
        return timestamp.atOffset(ZoneOffset.UTC).atZoneSameInstant(timezone).toLocalDate();
    }

    private String normalizedSubject(String subject) {
        return subject.replace("category ", "").replace("merchant ", "").replaceAll("\\s+", "_");
    }

    private String title(ProactiveInsightType type, String subject) {
        return switch (type) {
            case SPENDING_SPIKE -> "Spending is higher than usual";
            case CATEGORY_INCREASE -> "Category spending increased";
            case MERCHANT_INCREASE -> "Merchant spending increased";
            case WEEKEND_SPENDING_CHANGE -> "Weekend spending increased";
            case UNUSUAL_PURCHASE -> "Unusual purchase";
            case SPENDING_REDUCTION -> "Positive spending reduction";
        };
    }

    private String formatPercentage(Money current, Money baseline) {
        if (baseline.amount().signum() == 0) return "0";
        return current.amount().subtract(baseline.amount()).abs().multiply(BigDecimal.valueOf(100))
            .divide(baseline.amount(), 0, RoundingMode.HALF_UP).toPlainString();
    }

    private String hash(String input) {
        try {
            return java.util.HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(input.getBytes(StandardCharsets.UTF_8))).substring(0, 32);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }
}
