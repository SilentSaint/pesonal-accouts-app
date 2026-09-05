package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.BillStatement;
import com.automaticexpense.tracker.domain.Transaction;

import java.util.List;

public record StatementIngestionSummary(
    AccountId accountId,
    String cardName,
    BillStatement billStatement,
    int totalParsedTransactions,
    int newTransactionsIngested,
    int duplicatesMerged
) {}
