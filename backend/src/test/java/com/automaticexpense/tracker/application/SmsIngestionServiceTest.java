package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.out.TransactionRepositoryPort;
import com.automaticexpense.tracker.domain.ParsedTransactionEvent;
import com.automaticexpense.tracker.domain.SmsTransactionParser;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class SmsIngestionServiceTest {

    @Test
    void shouldParseAndSaveValidSmsTransaction() {
        FakeTransactionRepository repo = new FakeTransactionRepository();
        SmsTransactionParser parser = new SmsTransactionParser();
        SmsIngestionService service = new SmsIngestionService(parser, repo);

        String sender = "VM-HDFCBK";
        String body = "Rs 450.00 debited from a/c **1234 on 26-JUL-26 at STARBUCKS. Info: UPI/6291.";
        LocalDateTime receivedAt = LocalDateTime.of(2026, 7, 26, 14, 30);

        ParsedTransactionEvent result = service.ingestSms(sender, body, receivedAt);

        assertThat(result).isNotNull();
        assertThat(result.amount()).isEqualByComparingTo(new BigDecimal("450.00"));
        assertThat(repo.savedEvents).hasSize(1);
        assertThat(repo.savedEvents.get(0)).isEqualTo(result);
    }

    @Test
    void shouldNotSaveNonFinancialSms() {
        FakeTransactionRepository repo = new FakeTransactionRepository();
        SmsTransactionParser parser = new SmsTransactionParser();
        SmsIngestionService service = new SmsIngestionService(parser, repo);

        String sender = "JIO-MSG";
        String body = "Your OTP for logging in is 482910.";
        LocalDateTime receivedAt = LocalDateTime.of(2026, 7, 26, 11, 0);

        ParsedTransactionEvent result = service.ingestSms(sender, body, receivedAt);

        assertThat(result).isNull();
        assertThat(repo.savedEvents).isEmpty();
    }

    static class FakeTransactionRepository implements TransactionRepositoryPort {
        final List<ParsedTransactionEvent> savedEvents = new ArrayList<>();

        @Override
        public void saveTransaction(ParsedTransactionEvent event) {
            savedEvents.add(event);
        }
    }
}
