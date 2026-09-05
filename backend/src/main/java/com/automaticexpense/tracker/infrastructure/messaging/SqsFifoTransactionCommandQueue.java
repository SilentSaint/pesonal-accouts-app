package com.automaticexpense.tracker.infrastructure.messaging;

import com.automaticexpense.tracker.application.port.out.TransactionCommandQueue;
import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Map;
import java.util.Objects;

public final class SqsFifoTransactionCommandQueue implements TransactionCommandQueue {
    private static final ObjectMapper JSON = new ObjectMapper();

    private final SqsClient client;
    private final String queueUrl;

    public SqsFifoTransactionCommandQueue(SqsClient client, String queueUrl) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.queueUrl = Objects.requireNonNull(queueUrl, "queueUrl cannot be null");
    }

    @Override
    public void enqueue(TransactionCommandReference reference) {
        try {
            client.sendMessage(SendMessageRequest.builder()
                .queueUrl(queueUrl)
                .messageBody(JSON.writeValueAsString(Map.of(
                    "userScopeId", reference.userScopeId(),
                    "commandId", reference.commandId().value()
                )))
                .messageGroupId(reference.userScopeId())
                .messageDeduplicationId(deduplicationId(reference))
                .build());
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to serialize transaction command reference", exception);
        }
    }

    /**
     * Produces a FIFO-valid deduplication identifier scoped to the authenticated user.
     * A client command id is only unique within that user scope.
     */
    public static String deduplicationId(TransactionCommandReference reference) {
        Objects.requireNonNull(reference, "reference cannot be null");
        try {
            byte[] scopedReference = (reference.userScopeId() + "\u0000" + reference.commandId().value())
                .getBytes(StandardCharsets.UTF_8);
            return "cmd-" + java.util.HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(scopedReference)
            );
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }
}
