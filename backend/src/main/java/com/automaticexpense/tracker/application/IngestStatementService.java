package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.IngestStatementWebhookUseCase;
import com.automaticexpense.tracker.application.port.in.StatementIngestionSummary;
import com.automaticexpense.tracker.application.port.out.AccountRepository;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.*;

import java.time.LocalDateTime;
import java.util.*;

public class IngestStatementService implements IngestStatementWebhookUseCase {

    private final StatementParser statementParser;
    private final AccountRepository accountRepository;
    private final BillRepository billRepository;
    private final TransactionRepository transactionRepository;

    public IngestStatementService(
        StatementParser statementParser,
        AccountRepository accountRepository,
        BillRepository billRepository,
        Object unused, // for backwards compatibility in test wiring if needed
        TransactionRepository transactionRepository
    ) {
        this.statementParser = Objects.requireNonNull(statementParser, "statementParser cannot be null");
        this.accountRepository = Objects.requireNonNull(accountRepository, "accountRepository cannot be null");
        this.billRepository = Objects.requireNonNull(billRepository, "billRepository cannot be null");
        this.transactionRepository = Objects.requireNonNull(transactionRepository, "transactionRepository cannot be null");
    }

    public IngestStatementService(
        StatementParser statementParser,
        AccountRepository accountRepository,
        BillRepository billRepository,
        TransactionRepository transactionRepository
    ) {
        this.statementParser = Objects.requireNonNull(statementParser, "statementParser cannot be null");
        this.accountRepository = Objects.requireNonNull(accountRepository, "accountRepository cannot be null");
        this.billRepository = Objects.requireNonNull(billRepository, "billRepository cannot be null");
        this.transactionRepository = Objects.requireNonNull(transactionRepository, "transactionRepository cannot be null");
    }

    @Override
    public StatementIngestionSummary ingestStatementPayload(String rawPayload, IngestionSource source) {
        StatementExtractionResult result = statementParser.parse(rawPayload);

        // Auto-discover / resolve Account
        FinancialAccount account = accountRepository.findByLastFourDigits(result.cardIdentifier())
            .orElseGet(() -> {
                FinancialAccount newAcc = new FinancialAccount(
                    new AccountId("acc-card-" + result.cardIdentifier()),
                    result.cardName(),
                    AccountType.CREDIT_CARD,
                    result.cardIdentifier(),
                    result.totalDue().currency(),
                    Money.zero(result.totalDue().currency())
                );
                accountRepository.save(newAcc);
                return newAcc;
            });

        // Register / update Bill Statement
        BillStatement bill = billRepository.findByAccountIdAndStatementDate(
                account.id().value(), result.statementDate()
            )
            .map(existing -> existing.withStatementTerms(
                result.cardName(),
                result.totalDue(),
                result.minimumDue(),
                result.statementDate(),
                result.paymentDueDate()
            ))
            .orElseGet(() -> new BillStatement(
                UUID.randomUUID().toString(),
                account.id(),
                result.cardName(),
                result.totalDue(),
                result.minimumDue(),
                result.statementDate(),
                result.paymentDueDate()
            ));
        billRepository.save(bill);

        int newCount = 0;
        int dupCount = 0;

        for (StatementTransaction stTx : result.transactions()) {
            LocalDateTime stTxTime = stTx.date().atTime(12, 0);
            List<Transaction> existingInWindow = transactionRepository.findByAccountIdAndWindow(
                account.id(),
                stTxTime.minusDays(1),
                stTxTime.plusDays(1)
            );

            Transaction matchedExisting = null;
            for (Transaction ex : existingInWindow) {
                if (ex.amount().amount().compareTo(stTx.amount().amount()) == 0 &&
                    ex.type() == stTx.type() &&
                    isMerchantMatch(ex.merchantName(), stTx.merchantName())) {
                    matchedExisting = ex;
                    break;
                }
            }

            if (matchedExisting != null) {
                // Auto-merge with statement details
                Transaction merged = new Transaction(
                    matchedExisting.id(),
                    matchedExisting.amount(),
                    matchedExisting.type(),
                    matchedExisting.timestamp(),
                    matchedExisting.merchantName(),
                    matchedExisting.accountId(),
                    matchedExisting.categoryId(),
                    matchedExisting.ingestionSource(),
                    ReconciliationStatus.AUTO_MERGED,
                    matchedExisting.netPersonalExpense()
                );
                transactionRepository.save(merged);
                dupCount++;
            } else {
                // Ingest new statement transaction
                account.applyTransaction(stTx.amount(), stTx.type());
                accountRepository.save(account);

                Transaction newTx = new Transaction(
                    new TransactionId("stmt-tx-" + System.currentTimeMillis() + "-" + (int)(Math.random() * 1000)),
                    stTx.amount(),
                    stTx.type(),
                    stTxTime,
                    stTx.merchantName(),
                    account.id(),
                    "UNCATEGORIZED",
                    source != null ? source : IngestionSource.EMAIL,
                    ReconciliationStatus.CONFIRMED,
                    stTx.amount()
                );
                transactionRepository.save(newTx);
                newCount++;
            }
        }

        return new StatementIngestionSummary(
            account.id(),
            result.cardName(),
            bill,
            result.transactions().size(),
            newCount,
            dupCount
        );
    }

    private boolean isMerchantMatch(String m1, String m2) {
        if (m1 == null || m2 == null) return false;
        String norm1 = m1.trim().toLowerCase();
        String norm2 = m2.trim().toLowerCase();
        return norm1.equals(norm2) || norm1.contains(norm2) || norm2.contains(norm1);
    }
}
