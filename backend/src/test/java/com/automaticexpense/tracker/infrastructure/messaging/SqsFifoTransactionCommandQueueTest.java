package com.automaticexpense.tracker.infrastructure.messaging;

import com.automaticexpense.tracker.domain.TransactionCommandReference;
import com.automaticexpense.tracker.domain.TransactionId;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

import java.lang.reflect.Proxy;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

class SqsFifoTransactionCommandQueueTest {

    @Test
    void scopesFifoDeduplicationToTheUserWhileKeepingEachUsersMessageGroup() {
        TransactionCommandReference firstUser =
            new TransactionCommandReference("11111111111111111111111111111111", new TransactionId("client-command-001"));
        TransactionCommandReference secondUser =
            new TransactionCommandReference("22222222222222222222222222222222", new TransactionId("client-command-001"));
        AtomicReference<SendMessageRequest> sent = new AtomicReference<>();
        SqsClient client = (SqsClient) Proxy.newProxyInstance(
            getClass().getClassLoader(),
            new Class<?>[] { SqsClient.class },
            (proxy, method, arguments) -> {
                if ("sendMessage".equals(method.getName())) {
                    sent.set((SendMessageRequest) arguments[0]);
                }
                return null;
            }
        );

        new SqsFifoTransactionCommandQueue(client, "https://sqs.example/commands.fifo").enqueue(firstUser);

        assertThat(sent.get().messageGroupId()).isEqualTo(firstUser.userScopeId());
        assertThat(sent.get().messageDeduplicationId())
            .isEqualTo(SqsFifoTransactionCommandQueue.deduplicationId(firstUser))
            .matches("cmd-[a-f0-9]{64}")
            .isNotEqualTo(SqsFifoTransactionCommandQueue.deduplicationId(secondUser));
    }
}
