package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class SpendingAnalyticsCalculator {
    public static final FormulaReference FORMULA = new FormulaReference("spending-analytics", "1.0.0");

    public IntelligenceResult<SpendingAnalytics> evaluate(
        FinancialSnapshot snapshot,
        SpendingAnalyticsRequest request
    ) {
        EnumSet<IntelligenceWarning> warnings = EnumSet.noneOf(IntelligenceWarning.class);
        List<Transaction> matching = matchingTransactions(snapshot, request, warnings);
        PeriodSpending current = periodSpending(
            matching, request.period(), request.currency(), snapshot.timezone()
        );
        PeriodSpending previous = periodSpending(
            matching, request.period().previousEquivalent(), request.currency(), snapshot.timezone()
        );
        PeriodSpending yearOverYear = periodSpending(
            matching, request.period().yearEarlier(), request.currency(), snapshot.timezone()
        );

        List<PeriodSpending> rolling = rollingPeriods(matching, request, snapshot.timezone());
        if (rolling.stream().filter(period -> period.transactionCount() > 0).count()
            < request.rollingPeriodCount()) {
            warnings.add(IntelligenceWarning.INSUFFICIENT_HISTORY);
        }
        if (snapshot.asOf().atZone(snapshot.timezone()).toLocalDate().isBefore(request.period().end())) {
            warnings.add(IntelligenceWarning.INCOMPLETE_PERIOD);
        }
        PeriodComparison monthOverMonth = comparison(current, previous, warnings);
        PeriodComparison yearOverYearComparison = comparison(current, yearOverYear, warnings);

        List<Transaction> currentTransactions = transactionsIn(
            matching, request.period(), snapshot.timezone()
        );
        SpendingAnalytics analytics = new SpendingAnalytics(
            current,
            previous,
            yearOverYear,
            monthOverMonth,
            yearOverYearComparison,
            rollingAverage(rolling, request.currency()),
            current.transactionCount(),
            transactionAverage(currentTransactions, request.currency()),
            breakdown(currentTransactions, request.currency(), transaction ->
                transaction.categoryId() == null ? "UNCATEGORIZED" : transaction.categoryId()),
            breakdown(currentTransactions, request.currency(), Transaction::merchantName),
            breakdown(currentTransactions, request.currency(), transaction -> transaction.accountId().value()),
            largestPurchases(currentTransactions),
            rolling.stream().max(periodComparator()).orElse(current),
            rolling.stream().min(periodComparator()).orElse(current)
        );
        return new IntelligenceResult<>(
            IntelligenceClassification.FACT,
            analytics,
            snapshot.asOf(),
            snapshot.asOf(),
            BigDecimal.ONE,
            FORMULA,
            new EvidenceMetadata(current.transactionCount(), new DrillDownReference(
                request.period(), request.currency(), request.accountIds(),
                request.categoryId(), request.merchantName()
            )),
            List.of(
                "Only CONFIRMED and AUTO_MERGED debit records are canonical.",
                "Transfer-marked records are excluded from personal spending.",
                "Personal spending uses each record's netPersonalExpense, preserving reimbursable and lent portions."
            ),
            new ArrayList<>(warnings)
        );
    }

    private List<Transaction> matchingTransactions(
        FinancialSnapshot snapshot,
        SpendingAnalyticsRequest request,
        EnumSet<IntelligenceWarning> warnings
    ) {
        List<Transaction> matching = new ArrayList<>();
        for (Transaction transaction : snapshot.canonicalTransactions()) {
            if (transaction.timestamp().toInstant(ZoneOffset.UTC).isAfter(snapshot.asOf())) {
                warnings.add(IntelligenceWarning.STALE_SNAPSHOT);
                continue;
            }
            if (!transaction.amount().currency().equals(request.currency())) {
                warnings.add(IntelligenceWarning.MIXED_OR_UNSUPPORTED_CURRENCIES);
                continue;
            }
            if (!request.accountIds().isEmpty() && !request.accountIds().contains(transaction.accountId())) {
                continue;
            }
            if (request.categoryId() != null && !request.categoryId().equals(transaction.categoryId())) {
                continue;
            }
            if (request.merchantName() != null
                && !request.merchantName().equals(transaction.merchantName())) {
                continue;
            }
            if (transaction.reconciliationStatus() != ReconciliationStatus.CONFIRMED
                && transaction.reconciliationStatus() != ReconciliationStatus.AUTO_MERGED) {
                warnings.add(IntelligenceWarning.EXCLUDED_NON_CANONICAL_RECORDS);
                continue;
            }
            if (transaction.transferCounterpartMask() != null
                && !transaction.transferCounterpartMask().isBlank()) {
                warnings.add(IntelligenceWarning.EXCLUDED_TRANSFERS);
                continue;
            }
            if (transaction.type() == TransactionType.DEBIT) {
                matching.add(transaction);
            }
        }
        return matching;
    }

    private List<PeriodSpending> rollingPeriods(
        List<Transaction> transactions,
        SpendingAnalyticsRequest request,
        java.time.ZoneId timezone
    ) {
        List<PeriodSpending> periods = new ArrayList<>();
        DateRange period = request.period();
        for (int index = 0; index < request.rollingPeriodCount(); index++) {
            periods.add(periodSpending(transactions, period, request.currency(), timezone));
            period = period.previousEquivalent();
        }
        return periods;
    }

    private PeriodComparison comparison(
        PeriodSpending current,
        PeriodSpending baseline,
        EnumSet<IntelligenceWarning> warnings
    ) {
        Money change = current.total().subtract(baseline.total());
        if (baseline.total().amount().signum() == 0) {
            warnings.add(IntelligenceWarning.MISSING_COMPARISON_BASELINE);
            return new PeriodComparison(baseline, change, null);
        }
        BigDecimal percentage = change.amount()
            .multiply(BigDecimal.valueOf(100))
            .divide(baseline.total().amount(), 2, RoundingMode.HALF_UP);
        return new PeriodComparison(baseline, change, percentage);
    }

    private PeriodSpending periodSpending(
        List<Transaction> transactions,
        DateRange period,
        String currency,
        java.time.ZoneId timezone
    ) {
        List<Transaction> inPeriod = transactionsIn(transactions, period, timezone);
        Money total = inPeriod.stream()
            .map(Transaction::netPersonalExpense)
            .reduce(Money.zero(currency), Money::add);
        return new PeriodSpending(period, total, inPeriod.size());
    }

    private List<Transaction> transactionsIn(
        List<Transaction> transactions,
        DateRange period,
        java.time.ZoneId timezone
    ) {
        return transactions.stream()
            .filter(transaction -> period.contains(
                transaction.timestamp().atOffset(ZoneOffset.UTC).atZoneSameInstant(timezone).toLocalDate()
            ))
            .toList();
    }

    private Money rollingAverage(List<PeriodSpending> periods, String currency) {
        BigDecimal total = periods.stream()
            .map(period -> period.total().amount())
            .reduce(BigDecimal.ZERO, BigDecimal::add);
        return new Money(total.divide(BigDecimal.valueOf(periods.size()), 2, RoundingMode.HALF_UP), currency);
    }

    private Money transactionAverage(List<Transaction> transactions, String currency) {
        if (transactions.isEmpty()) {
            return Money.zero(currency);
        }
        BigDecimal total = transactions.stream()
            .map(transaction -> transaction.netPersonalExpense().amount())
            .reduce(BigDecimal.ZERO, BigDecimal::add);
        return new Money(total.divide(BigDecimal.valueOf(transactions.size()), 2, RoundingMode.HALF_UP), currency);
    }

    private List<SpendingBreakdown> breakdown(
        List<Transaction> transactions,
        String currency,
        java.util.function.Function<Transaction, String> key
    ) {
        Map<String, List<Transaction>> grouped = new LinkedHashMap<>();
        for (Transaction transaction : transactions) {
            grouped.computeIfAbsent(key.apply(transaction), ignored -> new ArrayList<>()).add(transaction);
        }
        return grouped.entrySet().stream()
            .map(entry -> new SpendingBreakdown(
                entry.getKey(),
                entry.getValue().stream().map(Transaction::netPersonalExpense)
                    .reduce(Money.zero(currency), Money::add),
                entry.getValue().size()
            ))
            .sorted(Comparator.comparing(
                (SpendingBreakdown entry) -> entry.total().amount()
            ).reversed().thenComparing(SpendingBreakdown::key))
            .toList();
    }

    private List<TransactionEvidence> largestPurchases(List<Transaction> transactions) {
        return transactions.stream()
            .sorted(Comparator.comparing(
                (Transaction transaction) -> transaction.netPersonalExpense().amount()
            ).reversed().thenComparing(transaction -> transaction.id().value()))
            .limit(5)
            .map(transaction -> new TransactionEvidence(
                transaction.id().value(), transaction.timestamp(), transaction.merchantName(),
                transaction.netPersonalExpense()
            ))
            .toList();
    }

    private Comparator<PeriodSpending> periodComparator() {
        return Comparator.comparing((PeriodSpending period) -> period.total().amount())
            .thenComparing(period -> period.period().start());
    }
}
