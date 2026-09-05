package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class StatementParserTest {

    @Test
    void shouldExtractStatementSummaryAndTransactionsFromCsvOrStructuredPayload() {
        String sampleStatementPayload = """
            Account: HDFC Credit Card Ending 4321
            Statement Date: 2026-08-15
            Total Due: 34500.00 INR
            Min Due: 2000.00 INR
            Payment Due Date: 2026-09-05
            ---
            2026-08-01,Swiggy,450.00,INR,DEBIT,REF-SWIGGY-101
            2026-08-03,Amazon,12499.00,INR,DEBIT,REF-AMZN-202
            2026-08-10,Salary Refund,1500.00,INR,CREDIT,REF-REFUND-303
            """;

        StatementParser parser = new StatementParser();
        StatementExtractionResult result = parser.parse(sampleStatementPayload);

        assertThat(result.cardIdentifier()).isEqualTo("4321");
        assertThat(result.cardName()).contains("HDFC Credit Card");
        assertThat(result.statementDate()).isEqualTo(LocalDate.of(2026, 8, 15));
        assertThat(result.totalDue()).isEqualTo(Money.of("34500.00", "INR"));
        assertThat(result.minimumDue()).isEqualTo(Money.of("2000.00", "INR"));
        assertThat(result.paymentDueDate()).isEqualTo(LocalDate.of(2026, 9, 5));

        List<StatementTransaction> txns = result.transactions();
        assertThat(txns).hasSize(3);

        StatementTransaction tx1 = txns.get(0);
        assertThat(tx1.merchantName()).isEqualTo("Swiggy");
        assertThat(tx1.amount()).isEqualTo(Money.of("450.00", "INR"));
        assertThat(tx1.type()).isEqualTo(TransactionType.DEBIT);
        assertThat(tx1.referenceNumber()).isEqualTo("REF-SWIGGY-101");
    }
}
