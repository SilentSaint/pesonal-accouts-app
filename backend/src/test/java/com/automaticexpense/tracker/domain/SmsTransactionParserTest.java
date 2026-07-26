package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;
import java.math.BigDecimal;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class SmsTransactionParserTest {

    @Test
    void shouldParseValidBankDebitSmsIntoTransactionEvent() {
        SmsTransactionParser parser = new SmsTransactionParser();

        String sender = "VM-HDFCBK";
        String body = "Rs 450.00 debited from a/c **1234 on 26-JUL-26 at STARBUCKS. Info: UPI/6291.";
        LocalDateTime receivedAt = LocalDateTime.of(2026, 7, 26, 14, 30);

        ParsedTransactionEvent event = parser.parse(sender, body, receivedAt);

        assertThat(event).isNotNull();
        assertThat(event.amount()).isEqualByComparingTo(new BigDecimal("450.00"));
        assertThat(event.currency()).isEqualTo("INR");
        assertThat(event.type()).isEqualTo(TransactionType.DEBIT);
        assertThat(event.accountLast4()).isEqualTo("1234");
        assertThat(event.merchantName()).isEqualTo("STARBUCKS");
        assertThat(event.timestamp()).isEqualTo(receivedAt);
    }

    @Test
    void shouldParseValidCreditSmsIntoTransactionEvent() {
        SmsTransactionParser parser = new SmsTransactionParser();

        String sender = "AD-ICICIB";
        String body = "INR 12,000.00 credited to a/c **5678 on 26-JUL-26 at SALARY. Info: NEFT/9981.";
        LocalDateTime receivedAt = LocalDateTime.of(2026, 7, 26, 10, 0);

        ParsedTransactionEvent event = parser.parse(sender, body, receivedAt);

        assertThat(event).isNotNull();
        assertThat(event.amount()).isEqualByComparingTo(new BigDecimal("12000.00"));
        assertThat(event.currency()).isEqualTo("INR");
        assertThat(event.type()).isEqualTo(TransactionType.CREDIT);
        assertThat(event.accountLast4()).isEqualTo("5678");
        assertThat(event.merchantName()).isEqualTo("SALARY");
        assertThat(event.timestamp()).isEqualTo(receivedAt);
    }

    @Test
    void shouldReturnNullForNonFinancialSms() {
        SmsTransactionParser parser = new SmsTransactionParser();

        String sender = "JIO-MSG";
        String body = "Your OTP for logging in is 482910. Valid for 10 minutes.";
        LocalDateTime receivedAt = LocalDateTime.of(2026, 7, 26, 11, 0);

        ParsedTransactionEvent event = parser.parse(sender, body, receivedAt);

        assertThat(event).isNull();
    }
}
