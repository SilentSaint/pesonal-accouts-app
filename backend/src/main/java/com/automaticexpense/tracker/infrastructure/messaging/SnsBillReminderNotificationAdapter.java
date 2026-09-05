package com.automaticexpense.tracker.infrastructure.messaging;

import com.automaticexpense.tracker.application.port.out.BillReminderNotificationPort;
import com.automaticexpense.tracker.domain.BillReminder;
import com.automaticexpense.tracker.domain.BillStatement;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.PublishRequest;

import java.util.Objects;

public final class SnsBillReminderNotificationAdapter implements BillReminderNotificationPort {
    private final SnsClient client;
    private final String topicArn;

    public SnsBillReminderNotificationAdapter(SnsClient client, String topicArn) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.topicArn = Objects.requireNonNull(topicArn, "topicArn cannot be null");
    }

    @Override
    public void send(BillReminder reminder, BillStatement bill) {
        client.publish(PublishRequest.builder()
            .topicArn(topicArn)
            .subject("Bill payment reminder")
            .message("""
                %s payment reminder
                Amount due: %s %s
                Payment due date: %s
                """.formatted(
                bill.cardName(),
                bill.remainingDue().currency(),
                bill.remainingDue().amount().toPlainString(),
                bill.dueDate()
            ))
            .build());
    }
}
