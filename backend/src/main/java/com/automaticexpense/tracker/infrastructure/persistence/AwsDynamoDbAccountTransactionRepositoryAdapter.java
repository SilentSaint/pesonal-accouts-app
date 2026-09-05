package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.AccountRepository;
import com.automaticexpense.tracker.application.port.out.AccountTransactionRepository;
import com.automaticexpense.tracker.application.port.out.CanonicalTransactionRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.FinancialAccount;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.DeleteItemRequest;
import software.amazon.awssdk.services.dynamodb.model.Delete;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;
import software.amazon.awssdk.services.dynamodb.model.Put;
import software.amazon.awssdk.services.dynamodb.model.TransactWriteItem;
import software.amazon.awssdk.services.dynamodb.model.TransactWriteItemsRequest;
import software.amazon.awssdk.services.dynamodb.model.TransactionCanceledException;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * DynamoDB implementation for the account and transaction repository seams.
 * The adapter is scoped to a verified principal before domain code can access it.
 */
public final class AwsDynamoDbAccountTransactionRepositoryAdapter
    implements AccountTransactionRepository, CanonicalTransactionRepository {

    private static final String USER_PREFIX = "USER#";
    private static final String ACCOUNT_PREFIX = "ACC#";
    private static final String TRANSACTION_PREFIX = "TXN#";

    private final DynamoDbClient client;
    private final String tableName;
    private final String userPartitionKey;

    public AwsDynamoDbAccountTransactionRepositoryAdapter(
        DynamoDbClient client,
        String tableName,
        String authenticatedUserId
    ) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.tableName = Objects.requireNonNull(tableName, "tableName cannot be null");
        this.userPartitionKey = USER_PREFIX + Objects.requireNonNull(
            authenticatedUserId,
            "authenticatedUserId cannot be null"
        );
    }

    @Override
    public void save(FinancialAccount account) {
        put(DynamoDbItem.fromAccount(userId(), account));
    }

    @Override
    public Optional<FinancialAccount> findById(AccountId id) {
        Map<String, AttributeValue> item = client.getItem(GetItemRequest.builder()
            .tableName(tableName)
            .key(key(ACCOUNT_PREFIX + id.value()))
            .consistentRead(true)
            .build()).item();
        return item.isEmpty() ? Optional.empty() : Optional.of(DynamoDbItem.toAccount(fromItem(item)));
    }

    @Override
    public Optional<FinancialAccount> findByLastFourDigits(String lastFourDigits) {
        return queryPrefix(ACCOUNT_PREFIX).stream()
            .map(this::fromItem)
            .filter(item -> lastFourDigits.equals(item.get("lastFourDigits")))
            .map(DynamoDbItem::toAccount)
            .findFirst();
    }

    @Override
    public void save(Transaction transaction) {
        put(DynamoDbItem.fromTransaction(userId(), transaction));
    }

    @Override
    public boolean saveAtomically(FinancialAccount account, Transaction transaction) {
        try {
            client.transactWriteItems(TransactWriteItemsRequest.builder()
                .transactItems(
                    TransactWriteItem.builder()
                        .put(Put.builder()
                            .tableName(tableName)
                            .item(toItem(DynamoDbItem.fromAccount(userId(), account)))
                            .build())
                        .build(),
                    TransactWriteItem.builder()
                        .put(Put.builder()
                            .tableName(tableName)
                            .item(toItem(DynamoDbItem.fromTransaction(userId(), transaction)))
                            .conditionExpression("attribute_not_exists(PK) AND attribute_not_exists(SK)")
                            .build())
                        .build())
                .build());
            return true;
        } catch (TransactionCanceledException exception) {
            boolean duplicateCommand = exception.cancellationReasons().stream()
                .anyMatch(reason -> "ConditionalCheckFailed".equals(reason.code()));
            if (duplicateCommand) {
                return false;
            }
            throw exception;
        }
    }

    @Override
    public boolean mergeCanonically(Transaction canonical, Transaction duplicate) {
        Optional<Map<String, String>> duplicateItem = findItemByTransactionId(duplicate.id());
        if (duplicateItem.isEmpty()) {
            return false;
        }
        try {
            client.transactWriteItems(TransactWriteItemsRequest.builder()
                .transactItems(
                    TransactWriteItem.builder()
                        .put(Put.builder()
                            .tableName(tableName)
                            .item(toItem(DynamoDbItem.fromTransaction(userId(), canonical)))
                            .build())
                        .build(),
                    TransactWriteItem.builder()
                        .delete(Delete.builder()
                            .tableName(tableName)
                            .key(key(duplicateItem.orElseThrow().get("SK")))
                            .conditionExpression("attribute_exists(PK) AND attribute_exists(SK)")
                            .build())
                        .build())
                .build());
            return true;
        } catch (TransactionCanceledException exception) {
            return false;
        }
    }

    @Override
    public boolean confirmAsSeparate(FinancialAccount account, Transaction transaction) {
        Optional<Map<String, String>> storedItem = findItemByTransactionId(transaction.id());
        if (storedItem.isEmpty()) {
            return false;
        }
        try {
            client.transactWriteItems(TransactWriteItemsRequest.builder()
                .transactItems(
                    TransactWriteItem.builder()
                        .put(Put.builder()
                            .tableName(tableName)
                            .item(toItem(DynamoDbItem.fromAccount(userId(), account)))
                            .build())
                        .build(),
                    TransactWriteItem.builder()
                        .put(Put.builder()
                            .tableName(tableName)
                            .item(toItem(DynamoDbItem.fromTransaction(userId(), transaction)))
                            .conditionExpression("attribute_exists(PK) AND attribute_exists(SK)")
                            .build())
                        .build())
                .build());
            return true;
        } catch (TransactionCanceledException exception) {
            return false;
        }
    }

    @Override
    public Optional<Transaction> findById(TransactionId id) {
        return queryPrefix(TRANSACTION_PREFIX).stream()
            .map(this::fromItem)
            .filter(item -> id.value().equals(item.get("txnId")))
            .map(DynamoDbItem::toTransaction)
            .findFirst();
    }

    @Override
    public List<Transaction> findByAccountId(AccountId accountId) {
        return transactions()
            .filter(transaction -> transaction.accountId().equals(accountId))
            .toList();
    }

    @Override
    public List<Transaction> findByReconciliationStatus(ReconciliationStatus status) {
        return transactions()
            .filter(transaction -> transaction.reconciliationStatus() == status)
            .toList();
    }

    @Override
    public List<Transaction> findByAccountIdAndWindow(
        AccountId accountId,
        LocalDateTime startTime,
        LocalDateTime endTime
    ) {
        return transactions()
            .filter(transaction -> transaction.accountId().equals(accountId))
            .filter(transaction -> !transaction.timestamp().isBefore(startTime))
            .filter(transaction -> !transaction.timestamp().isAfter(endTime))
            .toList();
    }

    @Override
    public List<Transaction> findAllTransactions() {
        return transactions().toList();
    }

    @Override
    public void delete(TransactionId id) {
        findItemByTransactionId(id).ifPresent(item -> client.deleteItem(DeleteItemRequest.builder()
            .tableName(tableName)
            .key(key(item.get("SK")))
            .build()));
    }

    private java.util.stream.Stream<Transaction> transactions() {
        return queryPrefix(TRANSACTION_PREFIX).stream()
            .map(this::fromItem)
            .filter(item -> item.containsKey("txnId"))
            .map(DynamoDbItem::toTransaction);
    }

    private Optional<Map<String, String>> findItemByTransactionId(TransactionId id) {
        return queryPrefix(TRANSACTION_PREFIX).stream()
            .map(this::fromItem)
            .filter(item -> id.value().equals(item.get("txnId")))
            .findFirst();
    }

    private List<Map<String, AttributeValue>> queryPrefix(String sortKeyPrefix) {
        List<Map<String, AttributeValue>> items = new ArrayList<>();
        Map<String, AttributeValue> startKey = null;
        do {
            QueryResponse response = client.query(QueryRequest.builder()
                .tableName(tableName)
                .keyConditionExpression("PK = :pk AND begins_with(SK, :sk)")
                .expressionAttributeValues(Map.of(
                    ":pk", AttributeValue.fromS(userPartitionKey),
                    ":sk", AttributeValue.fromS(sortKeyPrefix)
                ))
                .exclusiveStartKey(startKey)
                .scanIndexForward(false)
                .build());
            items.addAll(response.items());
            startKey = response.lastEvaluatedKey().isEmpty() ? null : response.lastEvaluatedKey();
        } while (startKey != null);
        return items;
    }

    private void put(Map<String, String> item) {
        client.putItem(PutItemRequest.builder()
            .tableName(tableName)
            .item(toItem(item))
            .build());
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
