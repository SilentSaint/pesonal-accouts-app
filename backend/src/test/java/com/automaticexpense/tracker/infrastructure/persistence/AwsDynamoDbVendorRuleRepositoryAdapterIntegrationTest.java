package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.IngestTransactionService;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.AccountType;
import com.automaticexpense.tracker.domain.FinancialAccount;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.Transaction;
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
class AwsDynamoDbVendorRuleRepositoryAdapterIntegrationTest {
    private DynamoDbClient client;
    private String tableName;

    @BeforeEach
    void createDisposableTable() {
        client = DynamoDbClient.builder()
            .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "ap-south-2")))
            .credentialsProvider(credentialsProvider())
            .build();
        tableName = "expense-tracker-vendor-rule-it-" + UUID.randomUUID().toString().replace("-", "");
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
    void learnsPersistsAcrossServiceRestartAndAppliesToALaterEmailIngestion() {
        AwsDynamoDbAccountTransactionRepositoryAdapter firstTransactions =
            new AwsDynamoDbAccountTransactionRepositoryAdapter(client, tableName, "user-a");
        AwsDynamoDbVendorRuleRepositoryAdapter firstRules =
            new AwsDynamoDbVendorRuleRepositoryAdapter(client, tableName, "user-a");
        firstTransactions.save(new FinancialAccount(
            new AccountId("acc-7788"), "HDFC Account", AccountType.SAVINGS, "7788", "INR",
            Money.of("5000.00", "INR")
        ));
        IngestTransactionService firstService = new IngestTransactionService(firstTransactions, firstRules);
        Transaction reviewed = firstService.ingestSmsTransaction(
            "HDFCBK", "Rs 150.00 debited from a/c **7788 at Saira Banu.",
            LocalDateTime.of(2026, 8, 29, 10, 0)
        );
        firstService.assignCategoryAndLearnRule(
            reviewed.id(), "Food & Dining", "Tea & Snacks", "Tea Stall"
        );

        IngestTransactionService restartedService = new IngestTransactionService(
            new AwsDynamoDbAccountTransactionRepositoryAdapter(client, tableName, "user-a"),
            new AwsDynamoDbVendorRuleRepositoryAdapter(client, tableName, "user-a")
        );
        Transaction reingested = restartedService.ingestEmailTransaction(
            "alerts@example.com", "Debit alert",
            "INR 200.00 debited from card ending in 7788 at Saira Banu Info: UPI.",
            LocalDateTime.of(2026, 8, 30, 10, 0)
        );

        assertThat(reingested.categoryId()).isEqualTo("Food & Dining");
        assertThat(reingested.subCategory()).isEqualTo("Tea & Snacks");
        assertThat(new AwsDynamoDbVendorRuleRepositoryAdapter(client, tableName, "user-b").findAll())
            .isEmpty();
    }

    private software.amazon.awssdk.auth.credentials.AwsCredentialsProvider credentialsProvider() {
        String credentialProcess = System.getenv("AWS_CREDENTIAL_PROCESS");
        if (credentialProcess != null && !credentialProcess.isBlank()) {
            return ProcessCredentialsProvider.builder().command(credentialProcess).build();
        }
        return DefaultCredentialsProvider.create();
    }
}
