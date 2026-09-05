package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.AccountType;
import com.automaticexpense.tracker.domain.FinancialAccount;
import com.automaticexpense.tracker.domain.IngestionSource;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.TransactionType;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.auth.credentials.ProcessCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeDefinition;
import software.amazon.awssdk.services.dynamodb.model.CreateTableRequest;
import software.amazon.awssdk.services.dynamodb.model.DeleteTableRequest;
import software.amazon.awssdk.services.dynamodb.model.KeySchemaElement;
import software.amazon.awssdk.services.dynamodb.model.KeyType;

import java.time.LocalDateTime;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@EnabledIfEnvironmentVariable(named = "RUN_DYNAMODB_INTEGRATION", matches = "true")
class AwsDynamoDbAccountTransactionRepositoryAdapterIntegrationTest {

    private DynamoDbClient client;
    private String tableName;
    private AwsDynamoDbAccountTransactionRepositoryAdapter repository;

    @BeforeEach
    void createDisposableTable() {
        client = DynamoDbClient.builder()
            .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "ap-south-2")))
            .credentialsProvider(credentialsProvider())
            .build();
        tableName = "expense-tracker-repository-it-" + UUID.randomUUID().toString().replace("-", "");
        client.createTable(CreateTableRequest.builder()
            .tableName(tableName)
            .billingMode("PAY_PER_REQUEST")
            .attributeDefinitions(
                AttributeDefinition.builder().attributeName("PK").attributeType("S").build(),
                AttributeDefinition.builder().attributeName("SK").attributeType("S").build()
            )
            .keySchema(
                KeySchemaElement.builder().attributeName("PK").keyType(KeyType.HASH).build(),
                KeySchemaElement.builder().attributeName("SK").keyType(KeyType.RANGE).build()
            )
            .build());
        client.waiter().waitUntilTableExists(request -> request.tableName(tableName));
        repository = new AwsDynamoDbAccountTransactionRepositoryAdapter(client, tableName, "repository-test");
    }

    @AfterEach
    void deleteDisposableTable() {
        if (client != null && tableName != null) {
            client.deleteTable(DeleteTableRequest.builder().tableName(tableName).build());
            client.waiter().waitUntilTableNotExists(request -> request.tableName(tableName));
            client.close();
        }
    }

    @Test
    void persistsAndReloadsAccountInsideTheAuthenticatedUserPartition() {
        FinancialAccount account = new FinancialAccount(
            new AccountId("acc-1001"),
            "SBI Savings",
            AccountType.SAVINGS,
            "1001",
            "INR",
            Money.of("5000.00", "INR")
        );

        repository.save(account);

        assertThat(repository.findById(account.id()))
            .hasValueSatisfying(saved -> assertThat(saved.currentBalance()).isEqualTo(Money.of("5000.00", "INR")));
        assertThat(repository.findByLastFourDigits("1001"))
            .hasValueSatisfying(saved -> assertThat(saved.name()).isEqualTo("SBI Savings"));
    }

    @Test
    void persistsAndReloadsTransactionsInChronologicalOrderWithoutDuplicateIds() {
        Transaction newer = transaction("txn-command-2", LocalDateTime.of(2026, 8, 28, 12, 1));
        Transaction older = transaction("txn-command-1", LocalDateTime.of(2026, 8, 28, 12, 0));

        repository.save(newer);
        repository.save(older);
        repository.save(newer);

        assertThat(repository.findAllTransactions())
            .extracting(Transaction::id)
            .extracting(TransactionId::value)
            .containsExactly("txn-command-2", "txn-command-1");
    }

    @Test
    void atomicallyPersistsTheAccountBalanceAndTransactionOnlyOncePerCommandId() {
        FinancialAccount account = new FinancialAccount(
            new AccountId("acc-1001"),
            "SBI Savings",
            AccountType.SAVINGS,
            "1001",
            "INR",
            Money.of("5000.00", "INR")
        );
        repository.save(account);
        account.applyTransaction(Money.of("125.00", "INR"), TransactionType.DEBIT);
        Transaction command = transaction("txn-command-idempotent", LocalDateTime.of(2026, 8, 28, 12, 0));

        boolean firstWrite = repository.saveAtomically(account, command);
        boolean retriedWrite = repository.saveAtomically(account, command);

        assertThat(firstWrite).isTrue();
        assertThat(retriedWrite).isFalse();
        assertThat(repository.findById(account.id()))
            .hasValueSatisfying(saved ->
                assertThat(saved.currentBalance()).isEqualTo(Money.of("4875.00", "INR")));
        assertThat(repository.findAllTransactions())
            .extracting(Transaction::id)
            .extracting(TransactionId::value)
            .containsExactly("txn-command-idempotent");
    }

    private Transaction transaction(String id, LocalDateTime timestamp) {
        return new Transaction(
            new TransactionId(id),
            Money.of("125.00", "INR"),
            TransactionType.DEBIT,
            timestamp,
            "Test Merchant",
            new AccountId("acc-1001"),
            "Food",
            IngestionSource.MANUAL,
            ReconciliationStatus.CONFIRMED,
            Money.of("125.00", "INR")
        );
    }

    private software.amazon.awssdk.auth.credentials.AwsCredentialsProvider credentialsProvider() {
        String credentialProcess = System.getenv("AWS_CREDENTIAL_PROCESS");
        if (credentialProcess != null && !credentialProcess.isBlank()) {
            return ProcessCredentialsProvider.builder()
                .command(credentialProcess)
                .build();
        }
        return DefaultCredentialsProvider.create();
    }
}
