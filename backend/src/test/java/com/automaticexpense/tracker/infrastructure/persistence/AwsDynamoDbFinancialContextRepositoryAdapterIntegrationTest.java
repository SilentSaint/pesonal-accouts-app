package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.ContextProvenance;
import com.automaticexpense.tracker.domain.FinancialContextCapability;
import com.automaticexpense.tracker.domain.FinancialContextItem;
import com.automaticexpense.tracker.domain.FinancialContextType;
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
import software.amazon.awssdk.services.dynamodb.model.KeySchemaElement;
import software.amazon.awssdk.services.dynamodb.model.KeyType;

import java.time.Instant;
import java.time.LocalDate;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@EnabledIfEnvironmentVariable(named = "RUN_DYNAMODB_INTEGRATION", matches = "true")
class AwsDynamoDbFinancialContextRepositoryAdapterIntegrationTest {
    private DynamoDbClient client;
    private String tableName;

    @BeforeEach
    void createDisposableTable() {
        client = DynamoDbClient.builder()
            .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "ap-south-2")))
            .credentialsProvider(credentialsProvider())
            .build();
        tableName = "expense-tracker-context-it-" + UUID.randomUUID().toString().replace("-", "");
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
    void persistsAcrossAdapterRecreationAndDoesNotExposeAnotherPrincipalsContext() {
        FinancialContextItem item = FinancialContextItem.create(
            "ctx-floor", FinancialContextType.PREFERRED_MINIMUM_CASH_BALANCE, "Cash floor",
            Map.of("amount", "25000.00", "currency", "INR"),
            Set.of(FinancialContextCapability.CASH_FLOW_FORECAST),
            ContextProvenance.USER_DECLARED, LocalDate.of(2026, 8, 1), null,
            Instant.parse("2026-08-01T10:00:00Z")
        );
        new AwsDynamoDbFinancialContextRepositoryAdapter(client, tableName, "principal-a").save(item);

        AwsDynamoDbFinancialContextRepositoryAdapter restarted =
            new AwsDynamoDbFinancialContextRepositoryAdapter(client, tableName, "principal-a");

        assertThat(restarted.findById("ctx-floor")).contains(item);
        assertThat(new AwsDynamoDbFinancialContextRepositoryAdapter(client, tableName, "principal-b").findAll())
            .isEmpty();
        restarted.delete("ctx-floor");
        assertThat(restarted.findById("ctx-floor")).isEmpty();
    }

    private software.amazon.awssdk.auth.credentials.AwsCredentialsProvider credentialsProvider() {
        String credentialProcess = System.getenv("AWS_CREDENTIAL_PROCESS");
        if (credentialProcess != null && !credentialProcess.isBlank()) {
            return ProcessCredentialsProvider.builder().command(credentialProcess).build();
        }
        return DefaultCredentialsProvider.create();
    }
}
