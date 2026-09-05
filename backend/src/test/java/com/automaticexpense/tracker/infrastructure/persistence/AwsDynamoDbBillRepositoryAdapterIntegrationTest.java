package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.BillReminder;
import com.automaticexpense.tracker.domain.BillReminderStatus;
import com.automaticexpense.tracker.domain.BillReminderTiming;
import com.automaticexpense.tracker.domain.BillStatement;
import com.automaticexpense.tracker.domain.BillStatus;
import com.automaticexpense.tracker.domain.Money;
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

import java.time.LocalDate;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@EnabledIfEnvironmentVariable(named = "RUN_DYNAMODB_INTEGRATION", matches = "true")
class AwsDynamoDbBillRepositoryAdapterIntegrationTest {
    private DynamoDbClient client;
    private String tableName;

    @BeforeEach
    void createDisposableTable() {
        client = DynamoDbClient.builder()
            .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "ap-south-2")))
            .credentialsProvider(credentialsProvider())
            .build();
        tableName = "expense-tracker-bill-it-" + UUID.randomUUID().toString().replace("-", "");
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
    void persistsIdempotentPaymentsAndReminderClaimsAcrossAdapterRestarts() {
        BillStatement bill = new BillStatement(
            "bill-aws-1",
            new AccountId("acc-card-1"),
            "HDFC Credit Card",
            Money.of("1000.00", "INR"),
            Money.of("100.00", "INR"),
            LocalDate.of(2026, 8, 15),
            LocalDate.of(2026, 9, 10)
        );
        AwsDynamoDbBillRepositoryAdapter writer = new AwsDynamoDbBillRepositoryAdapter(client, tableName, "user-a");
        writer.save(bill);

        AwsDynamoDbBillRepositoryAdapter restarted = new AwsDynamoDbBillRepositoryAdapter(client, tableName, "user-a");
        restarted.recordPaymentAtomically(bill.id(), "payment-1", Money.of("1000.00", "INR"));
        restarted.recordPaymentAtomically(bill.id(), "payment-1", Money.of("1000.00", "INR"));
        BillStatement paid = new AwsDynamoDbBillRepositoryAdapter(client, tableName, "user-a")
            .findBillById(bill.id()).orElseThrow();
        assertThat(paid.status()).isEqualTo(BillStatus.PAID);
        assertThat(paid.paidAmount()).isEqualTo(Money.of("1000.00", "INR"));

        BillReminder reminder = BillReminder.scheduledFor(bill, BillReminderTiming.FIVE_DAYS_BEFORE);
        assertThat(restarted.scheduleIfAbsent(reminder)).isTrue();
        assertThat(new AwsDynamoDbBillRepositoryAdapter(client, tableName, "user-a").scheduleIfAbsent(reminder)).isFalse();
        assertThat(restarted.claim(reminder.id())).contains(reminder.withStatus(BillReminderStatus.CLAIMED));
    }

    private software.amazon.awssdk.auth.credentials.AwsCredentialsProvider credentialsProvider() {
        String credentialProcess = System.getenv("AWS_CREDENTIAL_PROCESS");
        if (credentialProcess != null && !credentialProcess.isBlank()) {
            return ProcessCredentialsProvider.builder().command(credentialProcess).build();
        }
        return DefaultCredentialsProvider.create();
    }
}
