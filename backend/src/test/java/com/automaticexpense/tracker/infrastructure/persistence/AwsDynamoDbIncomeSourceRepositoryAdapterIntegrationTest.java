package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IncomeCadence;
import com.automaticexpense.tracker.domain.IncomeSource;
import com.automaticexpense.tracker.domain.IncomeSourceType;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.TransactionId;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.auth.credentials.ProcessCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeDefinition;
import software.amazon.awssdk.services.dynamodb.model.CreateTableRequest;
import software.amazon.awssdk.services.dynamodb.model.KeySchemaElement;
import software.amazon.awssdk.services.dynamodb.model.KeyType;

import java.time.LocalDate;
import java.util.UUID;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

@EnabledIfEnvironmentVariable(named = "RUN_DYNAMODB_INTEGRATION", matches = "true")
class AwsDynamoDbIncomeSourceRepositoryAdapterIntegrationTest {
    private DynamoDbClient client;
    private String tableName;

    @BeforeEach
    void createDisposableTable() {
        client = DynamoDbClient.builder()
            .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "ap-south-2")))
            .credentialsProvider(credentialsProvider())
            .build();
        tableName = "expense-tracker-income-it-" + UUID.randomUUID().toString().replace("-", "");
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
            client.deleteTable(request -> request.tableName(tableName));
            client.waiter().waitUntilTableNotExists(request -> request.tableName(tableName));
            client.close();
        }
    }

    @Test
    void persistsIncomeSourcesAcrossRepositoryRestartAndKeepsUsersIsolated() {
        IncomeSource source = IncomeSource.confirmed(
            "income-1", "Acme Payroll", IncomeSourceType.FIXED, Money.of("75000.00", "INR"),
            IncomeCadence.MONTHLY, LocalDate.of(2026, 1, 31), null, new AccountId("account-1"),
            Set.of(new TransactionId("credit-jan"))
        );
        AwsDynamoDbIncomeSourceRepositoryAdapter first =
            new AwsDynamoDbIncomeSourceRepositoryAdapter(client, tableName, "user-a");

        first.save(source);

        AwsDynamoDbIncomeSourceRepositoryAdapter restarted =
            new AwsDynamoDbIncomeSourceRepositoryAdapter(client, tableName, "user-a");
        assertThat(restarted.findById("income-1")).contains(source);
        assertThat(restarted.findAll()).containsExactly(source);
        assertThat(new AwsDynamoDbIncomeSourceRepositoryAdapter(client, tableName, "user-b").findAll()).isEmpty();
    }

    private AwsCredentialsProvider credentialsProvider() {
        String credentialProcess = System.getenv("AWS_CREDENTIAL_PROCESS");
        return credentialProcess != null && !credentialProcess.isBlank()
            ? ProcessCredentialsProvider.builder().command(credentialProcess).build()
            : DefaultCredentialsProvider.create();
    }
}
