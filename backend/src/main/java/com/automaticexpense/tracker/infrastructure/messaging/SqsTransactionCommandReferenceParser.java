package com.automaticexpense.tracker.infrastructure.messaging;

import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.automaticexpense.tracker.domain.TransactionId;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.regex.Pattern;

/**
 * Decodes only the durable reference carried on transaction command SQS queues.
 */
public final class SqsTransactionCommandReferenceParser {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final Pattern USER_SCOPE = Pattern.compile("[a-f0-9]{32}");

    private SqsTransactionCommandReferenceParser() {
    }

    public static TransactionCommandReference parse(String body) {
        try {
            JsonNode payload = JSON.readTree(body);
            if (payload == null) {
                throw new IllegalArgumentException("SQS command reference is required");
            }
            String userScopeId = requiredText(payload, "userScopeId");
            if (!USER_SCOPE.matcher(userScopeId).matches()) {
                throw new IllegalArgumentException("SQS command user scope is invalid");
            }
            return new TransactionCommandReference(userScopeId, new TransactionId(requiredText(payload, "commandId")));
        } catch (JsonProcessingException exception) {
            throw new IllegalArgumentException("SQS command reference is invalid", exception);
        }
    }

    private static String requiredText(JsonNode body, String field) {
        String value = body.path(field).asText(null);
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(field + " is required");
        }
        return value;
    }
}
