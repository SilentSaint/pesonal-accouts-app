package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class EmailTransactionParser {

    private static final Pattern AMOUNT_PATTERN = Pattern.compile("(?i)(?:rs|inr)\\.?\\s*([\\d,]+\\.?\\d*)");
    private static final Pattern ACCOUNT_PATTERN = Pattern.compile("(?i)(?:a/c|card|account|ending in)\\.?\\s*\\**(\\d{4})");
    private static final Pattern MERCHANT_PATTERN = Pattern.compile("(?i)\\bat\\s+([A-Za-z0-9_\\-\\s]+?)(?=\\.|\\s+on|\\s+Info|\\s*$)");

    public ParsedTransactionEvent parse(String sender, String subject, String body, LocalDateTime receivedAt) {
        String fullText = (subject != null ? subject : "") + " " + (body != null ? body : "");
        if (fullText.isBlank()) {
            return null;
        }

        Matcher amountMatcher = AMOUNT_PATTERN.matcher(fullText);
        if (!amountMatcher.find()) {
            return null;
        }
        BigDecimal amount = new BigDecimal(amountMatcher.group(1).replace(",", ""));

        String lowerText = fullText.toLowerCase();
        TransactionType type = (lowerText.contains("credited") || lowerText.contains("credit")) && !lowerText.contains("credit card")
            ? TransactionType.CREDIT
            : TransactionType.DEBIT;

        Matcher accountMatcher = ACCOUNT_PATTERN.matcher(fullText);
        String accountLast4 = accountMatcher.find() ? accountMatcher.group(1) : "UNKNOWN";

        Matcher merchantMatcher = MERCHANT_PATTERN.matcher(fullText);
        String merchantName = merchantMatcher.find() ? merchantMatcher.group(1).trim() : "UNKNOWN";

        return new ParsedTransactionEvent(
            amount,
            "INR",
            type,
            accountLast4,
            merchantName,
            receivedAt
        );
    }
}
