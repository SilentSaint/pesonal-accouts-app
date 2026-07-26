package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.IngestSmsTransactionUseCase;
import com.automaticexpense.tracker.application.port.out.TransactionRepositoryPort;
import com.automaticexpense.tracker.domain.ParsedTransactionEvent;
import com.automaticexpense.tracker.domain.SmsTransactionParser;

import java.time.LocalDateTime;

public class SmsIngestionService implements IngestSmsTransactionUseCase {

    private final SmsTransactionParser parser;
    private final TransactionRepositoryPort repositoryPort;

    public SmsIngestionService(SmsTransactionParser parser, TransactionRepositoryPort repositoryPort) {
        this.parser = parser;
        this.repositoryPort = repositoryPort;
    }

    @Override
    public ParsedTransactionEvent ingestSms(String sender, String body, LocalDateTime receivedAt) {
        ParsedTransactionEvent event = parser.parse(sender, body, receivedAt);
        if (event != null) {
            repositoryPort.saveTransaction(event);
        }
        return event;
    }
}
