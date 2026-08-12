package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;
import java.math.BigDecimal;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class EmailTransactionParserTest {

    @Test
    void shouldParseValidBankDebitEmailIntoTransactionEvent() {
        EmailTransactionParser parser = new EmailTransactionParser();

        String sender = "alerts@hdfcbank.net";
        String subject = "Transaction Alert: INR 1,250.00 spent on HDFC Card 1234";
        String body = "Dear Customer, INR 1,250.00 was debited from your card ending in 1234 at Amazon on 2026-07-26.";
        LocalDateTime receivedAt = LocalDateTime.of(2026, 7, 26, 15, 0);

        ParsedTransactionEvent event = parser.parse(sender, subject, body, receivedAt);

        assertThat(event).isNotNull();
        assertThat(event.amount()).isEqualByComparingTo(new BigDecimal("1250.00"));
        assertThat(event.currency()).isEqualTo("INR");
        assertThat(event.type()).isEqualTo(TransactionType.DEBIT);
        assertThat(event.accountLast4()).isEqualTo("1234");
        assertThat(event.merchantName()).isEqualTo("Amazon");
        assertThat(event.timestamp()).isEqualTo(receivedAt);
    }

    @Test
    void shouldParseValidCreditEmailIntoTransactionEvent() {
        EmailTransactionParser parser = new EmailTransactionParser();

        String sender = "no-reply@sbi.co.in";
        String subject = "Account Credit Notification";
        String body = "Your account **5678 has been credited with Rs 5,000.00 at Refund on 2026-07-26.";
        LocalDateTime receivedAt = LocalDateTime.of(2026, 7, 26, 16, 15);

        ParsedTransactionEvent event = parser.parse(sender, subject, body, receivedAt);

        assertThat(event).isNotNull();
        assertThat(event.amount()).isEqualByComparingTo(new BigDecimal("5000.00"));
        assertThat(event.currency()).isEqualTo("INR");
        assertThat(event.type()).isEqualTo(TransactionType.CREDIT);
        assertThat(event.accountLast4()).isEqualTo("5678");
        assertThat(event.merchantName()).isEqualTo("Refund");
        assertThat(event.timestamp()).isEqualTo(receivedAt);
    }

    @Test
    void shouldReturnNullForNonFinancialEmail() {
        EmailTransactionParser parser = new EmailTransactionParser();

        String sender = "newsletter@techcrunch.com";
        String subject = "Weekly Tech Newsletter";
        String body = "Check out the top tech stories of this week!";
        LocalDateTime receivedAt = LocalDateTime.of(2026, 7, 26, 17, 0);

        ParsedTransactionEvent event = parser.parse(sender, subject, body, receivedAt);

        assertThat(event).isNull();
    }
}
