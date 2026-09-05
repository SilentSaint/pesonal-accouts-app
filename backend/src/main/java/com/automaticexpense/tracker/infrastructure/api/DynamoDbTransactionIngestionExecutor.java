package com.automaticexpense.tracker.infrastructure.api;

import com.automaticexpense.tracker.application.CommandRejectedException;
import com.automaticexpense.tracker.application.IngestTransactionService;
import com.automaticexpense.tracker.application.TransactionCommand;
import com.automaticexpense.tracker.application.port.out.TransactionIngestionExecutor;
import com.automaticexpense.tracker.application.port.in.IngestTransactionCommand;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.AccountType;
import com.automaticexpense.tracker.domain.FinancialAccount;
import com.automaticexpense.tracker.domain.IngestionSource;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbAccountTransactionRepositoryAdapter;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbVendorRuleRepositoryAdapter;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.math.BigDecimal;
import java.util.Objects;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class DynamoDbTransactionIngestionExecutor implements TransactionIngestionExecutor {
    private static final String GMAIL_PLACEHOLDER_ACCOUNT_ID = "acc-gmail";
    private static final Pattern LAST_FOUR_DIGITS = Pattern.compile("(\\d{4})(?!.*\\d)");

    private final DynamoDbClient client;
    private final String tableName;

    public DynamoDbTransactionIngestionExecutor(DynamoDbClient client, String tableName) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
    }

    @Override
    public Transaction ingest(TransactionCommand command) {
        try {
            AwsDynamoDbAccountTransactionRepositoryAdapter transactions =
                new AwsDynamoDbAccountTransactionRepositoryAdapter(
                    client, tableName, command.userScopeId()
                );
            IngestTransactionCommand payload = resolveGmailAccount(command.payload(), transactions);
            return new IngestTransactionService(
                transactions,
                new AwsDynamoDbVendorRuleRepositoryAdapter(
                    client, tableName, command.userScopeId()
                )
            ).ingestManualTransaction(payload, command.id());
        } catch (IllegalArgumentException exception) {
            throw new CommandRejectedException("Transaction command rejected", exception);
        }
    }

    private IngestTransactionCommand resolveGmailAccount(
        IngestTransactionCommand command,
        AwsDynamoDbAccountTransactionRepositoryAdapter accounts
    ) {
        if (command.ingestionSource() != IngestionSource.EMAIL
            || !GMAIL_PLACEHOLDER_ACCOUNT_ID.equals(command.accountId().value())) {
            return command;
        }

        String lastFourDigits = extractLastFourDigits(command.accountMask());
        AccountId discoveredAccountId = new AccountId("acc-auto-" + lastFourDigits);
        accounts.findById(discoveredAccountId).orElseGet(() -> {
            FinancialAccount account = new FinancialAccount(
                discoveredAccountId,
                "Discovered Gmail Account " + lastFourDigits,
                AccountType.SAVINGS,
                lastFourDigits,
                command.amount().currency(),
                new Money(BigDecimal.ZERO, command.amount().currency())
            );
            accounts.save(account);
            return account;
        });

        return new IngestTransactionCommand(
            command.amount(),
            command.type(),
            command.timestamp(),
            command.merchantName(),
            discoveredAccountId,
            command.categoryId(),
            command.ingestionSource(),
            command.subCategory(),
            command.netPersonalExpense(),
            command.accountMask(),
            command.referenceNumber(),
            command.rawSnippet(),
            command.transferCounterpartMask()
        );
    }

    private String extractLastFourDigits(String accountMask) {
        if (accountMask == null) {
            throw new IllegalArgumentException("Gmail transactions require an account mask");
        }
        Matcher matcher = LAST_FOUR_DIGITS.matcher(accountMask);
        if (!matcher.find()) {
            throw new IllegalArgumentException("Gmail account mask must include four digits");
        }
        return matcher.group(1);
    }
}
