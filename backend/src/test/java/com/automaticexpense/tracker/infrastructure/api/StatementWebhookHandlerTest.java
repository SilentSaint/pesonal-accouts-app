package com.automaticexpense.tracker.infrastructure.api;

import com.automaticexpense.tracker.application.IngestStatementService;
import com.automaticexpense.tracker.application.IngestTransactionService;
import com.automaticexpense.tracker.application.port.out.AccountRepository;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.*;
import com.automaticexpense.tracker.infrastructure.persistence.DynamoDbSingleTableRepositoryAdapter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class StatementWebhookHandlerTest {

    private StatementWebhookHandler webhookHandler;

    @BeforeEach
    void setUp() {
        DynamoDbSingleTableRepositoryAdapter adapter = new DynamoDbSingleTableRepositoryAdapter("user-webhook");
        IngestTransactionService ingestTransactionService = new IngestTransactionService(
            adapter, adapter, adapter
        );
        IngestStatementService statementService = new IngestStatementService(
            new StatementParser(),
            adapter,
            adapter,
            ingestTransactionService,
            adapter
        );
        webhookHandler = new StatementWebhookHandler(statementService);
    }

    @Test
    void shouldHandleValidWebhookPayload() {
        String payload = """
            Account: Axis Bank Credit Card Ending 8899
            Statement Date: 2026-08-10
            Total Due: 18000.00 INR
            Min Due: 1000.00 INR
            Payment Due Date: 2026-08-30
            ---
            2026-08-02,Flipkart,3200.00,INR,DEBIT,TXN-FLIP-1
            2026-08-05,Uber,450.00,INR,DEBIT,TXN-UBER-2
            """;

        StatementWebhookHandler.WebhookResponse response = webhookHandler.handleWebhook(payload, "EMAIL");

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.summary()).isNotNull();
        assertThat(response.summary().totalParsedTransactions()).isEqualTo(2);
        assertThat(response.summary().newTransactionsIngested()).isEqualTo(2);
        assertThat(response.summary().billStatement().totalAmount()).isEqualTo(Money.of("18000.00", "INR"));
    }

    @Test
    void shouldReturn400ForEmptyPayload() {
        StatementWebhookHandler.WebhookResponse response = webhookHandler.handleWebhook("", "EMAIL");
        assertThat(response.statusCode()).isEqualTo(400);
    }
}
