package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.BillReminderRepository;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.domain.BillReminder;
import com.automaticexpense.tracker.domain.BillReminderStatus;
import com.automaticexpense.tracker.domain.BillStatement;
import com.automaticexpense.tracker.domain.Money;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.ReturnValue;
import software.amazon.awssdk.services.dynamodb.model.UpdateItemRequest;

import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * Per-principal DynamoDB adapter for persisted bill statements and reminder deliveries.
 * Conditional writes make a payment transaction idempotent across Lambda retries.
 */
public final class AwsDynamoDbBillRepositoryAdapter implements BillRepository, BillReminderRepository {
    private static final String USER_PREFIX = "USER#";
    private static final String BILL_PREFIX = "BILL#";
    private static final String REMINDER_PREFIX = "BILL_REMINDER#";
    private static final int MAX_PAYMENT_WRITE_ATTEMPTS = 3;

    private final DynamoDbClient client;
    private final String tableName;
    private final String userPartitionKey;

    public AwsDynamoDbBillRepositoryAdapter(
        DynamoDbClient client,
        String tableName,
        String authenticatedUserId
    ) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
        this.userPartitionKey = USER_PREFIX + Objects.requireNonNull(
            authenticatedUserId, "authenticatedUserId cannot be null"
        );
    }

    @Override
    public void save(BillStatement bill) {
        put(DynamoDbItem.fromBillStatement(userId(), bill));
    }

    @Override
    public Optional<BillStatement> findBillById(String billId) {
        Map<String, AttributeValue> item = client.getItem(GetItemRequest.builder()
            .tableName(tableName)
            .key(key(BILL_PREFIX + billId))
            .consistentRead(true)
            .build()).item();
        return item.isEmpty() ? Optional.empty() : Optional.of(DynamoDbItem.toBillStatement(fromItem(item)));
    }

    @Override
    public List<BillStatement> findPendingBills() {
        return queryPrefix(BILL_PREFIX).stream()
            .map(this::fromItem)
            .map(DynamoDbItem::toBillStatement)
            .filter(bill -> !bill.isPaid())
            .toList();
    }

    @Override
    public List<BillStatement> findAllBills() {
        return queryPrefix(BILL_PREFIX).stream()
            .map(this::fromItem)
            .map(DynamoDbItem::toBillStatement)
            .toList();
    }

    @Override
    public Optional<BillStatement> recordPaymentAtomically(
        String billId,
        String paymentTransactionId,
        Money paymentAmount
    ) {
        for (int attempt = 0; attempt < MAX_PAYMENT_WRITE_ATTEMPTS; attempt++) {
            BillStatement stored = findBillById(billId).orElse(null);
            if (stored == null || stored.recordedPaymentTransactionIds().contains(paymentTransactionId)) {
                return Optional.ofNullable(stored);
            }

            stored.recordPayment(paymentTransactionId, paymentAmount);
            BillStatement updated = stored.withIncrementedVersion();
            try {
                client.putItem(PutItemRequest.builder()
                    .tableName(tableName)
                    .item(toItem(DynamoDbItem.fromBillStatement(userId(), updated)))
                    .conditionExpression("attribute_not_exists(#version) OR #version = :expectedVersion")
                    .expressionAttributeNames(Map.of("#version", "version"))
                    .expressionAttributeValues(Map.of(
                        ":expectedVersion", AttributeValue.fromS(Long.toString(stored.version()))
                    ))
                    .build());
                return Optional.of(updated);
            } catch (ConditionalCheckFailedException ignored) {
                // Re-read the statement: a competing payment may have completed first.
            }
        }
        throw new IllegalStateException("Could not atomically record payment for bill: " + billId);
    }

    @Override
    public boolean scheduleIfAbsent(BillReminder reminder) {
        try {
            client.putItem(PutItemRequest.builder()
                .tableName(tableName)
                .item(toItem(DynamoDbItem.fromBillReminder(userId(), reminder)))
                .conditionExpression("attribute_not_exists(PK) AND attribute_not_exists(SK)")
                .build());
            return true;
        } catch (ConditionalCheckFailedException ignored) {
            return false;
        }
    }

    @Override
    public List<BillReminder> findScheduledFor(LocalDate date) {
        return queryPrefix(REMINDER_PREFIX).stream()
            .map(this::fromItem)
            .map(DynamoDbItem::toBillReminder)
            .filter(reminder -> reminder.scheduledFor().equals(date))
            .filter(reminder -> reminder.status() == BillReminderStatus.SCHEDULED)
            .toList();
    }

    @Override
    public Optional<BillReminder> claim(String reminderId) {
        try {
            Map<String, AttributeValue> item = client.updateItem(UpdateItemRequest.builder()
                .tableName(tableName)
                .key(key(REMINDER_PREFIX + reminderId))
                .updateExpression("SET #status = :claimed")
                .conditionExpression("#status = :scheduled")
                .expressionAttributeNames(Map.of("#status", "status"))
                .expressionAttributeValues(Map.of(
                    ":claimed", AttributeValue.fromS(BillReminderStatus.CLAIMED.name()),
                    ":scheduled", AttributeValue.fromS(BillReminderStatus.SCHEDULED.name())
                ))
                .returnValues(ReturnValue.ALL_NEW)
                .build()).attributes();
            return Optional.of(DynamoDbItem.toBillReminder(fromItem(item)));
        } catch (ConditionalCheckFailedException ignored) {
            return Optional.empty();
        }
    }

    @Override
    public void markDelivered(String reminderId) {
        updateReminderStatus(reminderId, BillReminderStatus.CLAIMED, BillReminderStatus.DELIVERED);
    }

    @Override
    public void releaseClaim(String reminderId) {
        updateReminderStatus(reminderId, BillReminderStatus.CLAIMED, BillReminderStatus.SCHEDULED);
    }

    @Override
    public void cancel(String reminderId) {
        client.updateItem(UpdateItemRequest.builder()
            .tableName(tableName)
            .key(key(REMINDER_PREFIX + reminderId))
            .updateExpression("SET #status = :cancelled")
            .expressionAttributeNames(Map.of("#status", "status"))
            .expressionAttributeValues(Map.of(
                ":cancelled", AttributeValue.fromS(BillReminderStatus.CANCELLED.name())
            ))
            .build());
    }

    private void updateReminderStatus(
        String reminderId,
        BillReminderStatus expected,
        BillReminderStatus updated
    ) {
        client.updateItem(UpdateItemRequest.builder()
            .tableName(tableName)
            .key(key(REMINDER_PREFIX + reminderId))
            .updateExpression("SET #status = :updated")
            .conditionExpression("#status = :expected")
            .expressionAttributeNames(Map.of("#status", "status"))
            .expressionAttributeValues(Map.of(
                ":expected", AttributeValue.fromS(expected.name()),
                ":updated", AttributeValue.fromS(updated.name())
            ))
            .build());
    }

    private List<Map<String, AttributeValue>> queryPrefix(String sortKeyPrefix) {
        return client.query(QueryRequest.builder()
            .tableName(tableName)
            .keyConditionExpression("PK = :pk AND begins_with(SK, :sk)")
            .expressionAttributeValues(Map.of(
                ":pk", AttributeValue.fromS(userPartitionKey),
                ":sk", AttributeValue.fromS(sortKeyPrefix)
            ))
            .build()).items();
    }

    private void put(Map<String, String> item) {
        client.putItem(PutItemRequest.builder().tableName(tableName).item(toItem(item)).build());
    }

    private Map<String, AttributeValue> key(String sortKey) {
        return Map.of(
            "PK", AttributeValue.fromS(userPartitionKey),
            "SK", AttributeValue.fromS(sortKey)
        );
    }

    private Map<String, AttributeValue> toItem(Map<String, String> item) {
        Map<String, AttributeValue> result = new HashMap<>();
        item.forEach((name, value) -> result.put(name, AttributeValue.fromS(value)));
        return result;
    }

    private Map<String, String> fromItem(Map<String, AttributeValue> item) {
        Map<String, String> result = new HashMap<>();
        item.forEach((name, value) -> result.put(name, value.s()));
        return result;
    }

    private String userId() {
        return userPartitionKey.substring(USER_PREFIX.length());
    }
}
