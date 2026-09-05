package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.FinancialAnalyticsUseCase;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.*;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

public class FinancialAnalyticsService implements FinancialAnalyticsUseCase {

    private final TransactionRepository transactionRepository;

    public FinancialAnalyticsService(TransactionRepository transactionRepository) {
        this.transactionRepository = Objects.requireNonNull(transactionRepository, "transactionRepository cannot be null");
    }

    @Override
    public AnalyticsSummary generateMonthlyAnalytics(String yearMonth, String currency) {
        String targetYm = (yearMonth != null && !yearMonth.isBlank()) ? yearMonth : java.time.LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM"));
        String curr = currency != null ? currency : "INR";

        List<Transaction> allTxns = transactionRepository.findAllTransactions().stream()
            .filter(t -> t.timestamp().format(DateTimeFormatter.ofPattern("yyyy-MM")).equals(targetYm))
            .filter(t -> t.amount().currency().equalsIgnoreCase(curr))
            .toList();

        Money totalSpent = Money.zero(curr);
        Money totalIncome = Money.zero(curr);
        Map<String, BigDecimal> categorySpendMap = new HashMap<>();
        Map<String, BigDecimal> vendorSpendMap = new HashMap<>();

        for (Transaction t : allTxns) {
            if (t.type() == TransactionType.DEBIT) {
                totalSpent = totalSpent.add(t.netPersonalExpense());

                String cat = t.categoryId() != null ? t.categoryId() : "UNCATEGORIZED";
                categorySpendMap.merge(cat, t.netPersonalExpense().amount(), BigDecimal::add);

                vendorSpendMap.merge(t.merchantName(), t.netPersonalExpense().amount(), BigDecimal::add);
            } else if (t.type() == TransactionType.CREDIT) {
                totalIncome = totalIncome.add(t.amount());
            }
        }

        Money netSavings = totalIncome.subtract(totalSpent);

        Money avgSize = Money.zero(curr);
        long debitCount = allTxns.stream().filter(t -> t.type() == TransactionType.DEBIT).count();
        if (debitCount > 0) {
            BigDecimal avg = totalSpent.amount().divide(BigDecimal.valueOf(debitCount), 2, RoundingMode.HALF_UP);
            avgSize = new Money(avg, curr);
        }

        String topVendor = "N/A";
        Money topVendorSpend = Money.zero(curr);
        if (!vendorSpendMap.isEmpty()) {
            Map.Entry<String, BigDecimal> top = vendorSpendMap.entrySet().stream()
                .max(Map.Entry.comparingByValue())
                .orElseThrow();
            topVendor = top.getKey();
            topVendorSpend = new Money(top.getValue(), curr);
        }

        List<CategorySpendSummary> categories = new ArrayList<>();
        for (Map.Entry<String, BigDecimal> entry : categorySpendMap.entrySet()) {
            double pct = 0.0;
            if (totalSpent.amount().compareTo(BigDecimal.ZERO) > 0) {
                pct = entry.getValue().multiply(BigDecimal.valueOf(100))
                    .divide(totalSpent.amount(), 2, RoundingMode.HALF_UP)
                    .doubleValue();
            }
            categories.add(new CategorySpendSummary(
                entry.getKey(),
                entry.getKey(),
                new Money(entry.getValue(), curr),
                pct
            ));
        }

        List<String> aiInsights = new ArrayList<>();
        if (totalIncome.amount().compareTo(BigDecimal.ZERO) > 0) {
            double savingsRate = netSavings.amount().multiply(BigDecimal.valueOf(100))
                .divide(totalIncome.amount(), 1, RoundingMode.HALF_UP)
                .doubleValue();
            aiInsights.add("Healthy Savings Rate: You saved " + savingsRate + "% of your total income this month.");
        }
        if (!topVendor.equals("N/A")) {
            aiInsights.add("Top Spending Merchant: " + topVendor + " accounted for ₹" + topVendorSpend.amount().toPlainString() + ".");
        }
        if (categories.size() > 0) {
            aiInsights.add("Identified " + categories.size() + " active spending categories across your accounts.");
        }

        return new AnalyticsSummary(
            targetYm,
            totalSpent,
            totalIncome,
            netSavings,
            allTxns.size(),
            avgSize,
            topVendor,
            topVendorSpend,
            categories,
            aiInsights
        );
    }

    @Override
    public String exportTransactionsToCsv(String yearMonth) {
        List<Transaction> txns = getFilteredTransactions(yearMonth);
        StringBuilder sb = new StringBuilder();
        sb.append("Id,Amount,Currency,Type,Date,Merchant,Category,ReconciliationStatus\n");
        for (Transaction t : txns) {
            sb.append(String.format("%s,%s,%s,%s,%s,\"%s\",%s,%s\n",
                t.id().value(),
                t.amount().amount().toPlainString(),
                t.amount().currency(),
                t.type().name(),
                t.timestamp().toString(),
                t.merchantName().replace("\"", "\"\""),
                t.categoryId() != null ? t.categoryId() : "UNCATEGORIZED",
                t.reconciliationStatus().name()
            ));
        }
        return sb.toString();
    }

    @Override
    public String exportTransactionsToJson(String yearMonth) {
        List<Transaction> txns = getFilteredTransactions(yearMonth);
        StringBuilder sb = new StringBuilder();
        sb.append("[\n");
        for (int i = 0; i < txns.size(); i++) {
            Transaction t = txns.get(i);
            sb.append("  {\n")
              .append("    \"id\": \"").append(t.id().value()).append("\",\n")
              .append("    \"amount\": ").append(t.amount().amount().toPlainString()).append(",\n")
              .append("    \"currency\": \"").append(t.amount().currency()).append("\",\n")
              .append("    \"type\": \"").append(t.type().name()).append("\",\n")
              .append("    \"timestamp\": \"").append(t.timestamp().toString()).append("\",\n")
              .append("    \"merchantName\": \"").append(t.merchantName().replace("\"", "\\\"")).append("\",\n")
              .append("    \"categoryId\": \"").append(t.categoryId() != null ? t.categoryId() : "UNCATEGORIZED").append("\",\n")
              .append("    \"status\": \"").append(t.reconciliationStatus().name()).append("\"\n")
              .append("  }").append(i < txns.size() - 1 ? "," : "").append("\n");
        }
        sb.append("]");
        return sb.toString();
    }

    private List<Transaction> getFilteredTransactions(String yearMonth) {
        if (yearMonth == null || yearMonth.isBlank()) {
            return transactionRepository.findAllTransactions();
        }
        return transactionRepository.findAllTransactions().stream()
            .filter(t -> t.timestamp().format(DateTimeFormatter.ofPattern("yyyy-MM")).equals(yearMonth))
            .toList();
    }
}
