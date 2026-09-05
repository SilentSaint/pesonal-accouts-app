package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class StatementParser {

    private static final Pattern CARD_PATTERN = Pattern.compile("Account:\\s*(.+)", Pattern.CASE_INSENSITIVE);
    private static final Pattern STMT_DATE_PATTERN = Pattern.compile("Statement Date:\\s*(\\d{4}-\\d{2}-\\d{2})", Pattern.CASE_INSENSITIVE);
    private static final Pattern TOTAL_DUE_PATTERN = Pattern.compile("Total Due:\\s*([\\d,]+(?:\\.\\d{2})?)\\s*([A-Za-z]{3})?", Pattern.CASE_INSENSITIVE);
    private static final Pattern MIN_DUE_PATTERN = Pattern.compile("Min Due:\\s*([\\d,]+(?:\\.\\d{2})?)\\s*([A-Za-z]{3})?", Pattern.CASE_INSENSITIVE);
    private static final Pattern DUE_DATE_PATTERN = Pattern.compile("Payment Due Date:\\s*(\\d{4}-\\d{2}-\\d{2})", Pattern.CASE_INSENSITIVE);

    public StatementExtractionResult parse(String rawPayload) {
        if (rawPayload == null || rawPayload.isBlank()) {
            throw new IllegalArgumentException("Statement payload cannot be blank");
        }

        String cardName = "Credit Card";
        String cardIdentifier = "0000";
        LocalDate statementDate = LocalDate.now();
        Money totalDue = Money.zero("INR");
        Money minimumDue = Money.zero("INR");
        LocalDate paymentDueDate = LocalDate.now().plusDays(20);
        List<StatementTransaction> transactions = new ArrayList<>();

        String[] parts = rawPayload.split("---");
        String header = parts[0];

        Matcher cardMatcher = CARD_PATTERN.matcher(header);
        if (cardMatcher.find()) {
            String fullLine = cardMatcher.group(1).trim();
            cardName = fullLine;
            Matcher digitMatcher = Pattern.compile("(\\d{4})").matcher(fullLine);
            if (digitMatcher.find()) {
                cardIdentifier = digitMatcher.group(1);
            }
        }

        Matcher stmtDateMatcher = STMT_DATE_PATTERN.matcher(header);
        if (stmtDateMatcher.find()) {
            statementDate = LocalDate.parse(stmtDateMatcher.group(1));
        }

        Matcher totalDueMatcher = TOTAL_DUE_PATTERN.matcher(header);
        if (totalDueMatcher.find()) {
            String amtStr = totalDueMatcher.group(1).replace(",", "");
            String currency = totalDueMatcher.group(2) != null ? totalDueMatcher.group(2) : "INR";
            totalDue = new Money(new BigDecimal(amtStr), currency);
        }

        Matcher minDueMatcher = MIN_DUE_PATTERN.matcher(header);
        if (minDueMatcher.find()) {
            String amtStr = minDueMatcher.group(1).replace(",", "");
            String currency = minDueMatcher.group(2) != null ? minDueMatcher.group(2) : totalDue.currency();
            minimumDue = new Money(new BigDecimal(amtStr), currency);
        }

        Matcher dueDateMatcher = DUE_DATE_PATTERN.matcher(header);
        if (dueDateMatcher.find()) {
            paymentDueDate = LocalDate.parse(dueDateMatcher.group(1));
        }

        if (parts.length > 1) {
            String txSection = parts[1];
            String[] lines = txSection.split("\\r?\\n");
            for (String line : lines) {
                String trimmed = line.trim();
                if (trimmed.isEmpty() || trimmed.startsWith("#")) continue;
                String[] cols = trimmed.split(",");
                if (cols.length >= 5) {
                    LocalDate date = LocalDate.parse(cols[0].trim());
                    String merchant = cols[1].trim();
                    BigDecimal amt = new BigDecimal(cols[2].trim().replace(",", ""));
                    String curr = cols[3].trim();
                    TransactionType type = TransactionType.valueOf(cols[4].trim().toUpperCase());
                    String ref = cols.length > 5 ? cols[5].trim() : null;

                    transactions.add(new StatementTransaction(
                        date,
                        merchant,
                        new Money(amt, curr),
                        type,
                        ref
                    ));
                }
            }
        }

        return new StatementExtractionResult(
            cardIdentifier,
            cardName,
            statementDate,
            totalDue,
            minimumDue,
            paymentDueDate,
            transactions
        );
    }
}
