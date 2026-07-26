package com.automaticexpense.tracker.domain;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class SmsTransactionParser {

    private static final Pattern AMOUNT_PATTERN = Pattern.compile("(?i)(?:rs|inr)\\.?\\s*([\\d,]+\\.?\\d*)");
    private static final Pattern ACCOUNT_PATTERN = Pattern.compile("(?i)(?:a/c|card|acc)\\.?\\s*\\**(\\d{4})");
    private static final Pattern MERCHANT_PATTERN = Pattern.compile("(?i)\\bat\\s+([A-Za-z0-9_\\-\\s]+?)(?=\\.|\\s+Info|\\s+on|\\s*$)");

    public ParsedTransactionEvent parse(String sender, String body, LocalDateTime receivedAt) {
        if (body == null || body.isBlank()) {
            return null;
        }

        Matcher amountMatcher = AMOUNT_PATTERN.matcher(body);
        if (!amountMatcher.find()) {
            return null;
        }
        BigDecimal amount = new BigDecimal(amountMatcher.group(1).replace(",", ""));

        TransactionType type = body.toLowerCase().contains("credited") ? TransactionType.CREDIT : TransactionType.DEBIT;

        Matcher accountMatcher = ACCOUNT_PATTERN.matcher(body);
        String accountLast4 = accountMatcher.find() ? accountMatcher.group(1) : "UNKNOWN";

        Matcher merchantMatcher = MERCHANT_PATTERN.matcher(body);
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
