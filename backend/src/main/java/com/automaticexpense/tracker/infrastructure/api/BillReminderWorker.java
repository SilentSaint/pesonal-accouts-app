package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.automaticexpense.tracker.application.BillReminderScheduler;
import com.automaticexpense.tracker.application.port.out.BillReminderNotificationPort;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.domain.BillReminder;
import com.automaticexpense.tracker.domain.BillStatement;
import com.automaticexpense.tracker.infrastructure.messaging.SnsBillReminderNotificationAdapter;
import com.automaticexpense.tracker.infrastructure.persistence.AwsDynamoDbBillRepositoryAdapter;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.sns.SnsClient;

import java.time.LocalDate;
import java.util.Map;
import java.util.Objects;

public final class BillReminderWorker implements RequestHandler<Map<String, String>, Void> {
    private final BillReminderScheduler scheduler;
    private final BillRepository billRepository;
    private final BillReminderNotificationPort notificationPort;

    public BillReminderWorker() {
        AwsDynamoDbBillRepositoryAdapter bills = new AwsDynamoDbBillRepositoryAdapter(
            DynamoDbClient.create(), requiredEnvironment("TABLE_NAME"), requiredEnvironment("USER_ID")
        );
        this.scheduler = new BillReminderScheduler(bills, bills);
        this.billRepository = bills;
        this.notificationPort = new SnsBillReminderNotificationAdapter(
            SnsClient.create(), requiredEnvironment("BILL_REMINDER_TOPIC_ARN")
        );
    }

    public BillReminderWorker(
        BillReminderScheduler scheduler,
        BillRepository billRepository,
        BillReminderNotificationPort notificationPort
    ) {
        this.scheduler = Objects.requireNonNull(scheduler, "scheduler cannot be null");
        this.billRepository = Objects.requireNonNull(billRepository, "billRepository cannot be null");
        this.notificationPort = Objects.requireNonNull(notificationPort, "notificationPort cannot be null");
    }

    @Override
    public Void handleRequest(Map<String, String> event, Context context) {
        LocalDate today = event != null && event.get("date") != null
            ? LocalDate.parse(event.get("date"))
            : LocalDate.now();
        for (BillReminder reminder : scheduler.claimDueReminders(today)) {
            BillStatement bill = billRepository.findBillById(reminder.billId()).orElse(null);
            if (bill == null || bill.isPaid()) {
                scheduler.releaseClaim(reminder);
                continue;
            }
            try {
                notificationPort.send(reminder, bill);
                scheduler.markDelivered(reminder);
            } catch (RuntimeException exception) {
                scheduler.releaseClaim(reminder);
                throw exception;
            }
        }
        return null;
    }

    private static String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(name + " is not configured");
        }
        return value;
    }
}
