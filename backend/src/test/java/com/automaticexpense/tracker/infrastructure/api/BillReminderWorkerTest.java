package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.automaticexpense.tracker.application.BillReminderScheduler;
import com.automaticexpense.tracker.application.port.out.BillReminderNotificationPort;
import com.automaticexpense.tracker.application.port.out.BillReminderRepository;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.BillReminder;
import com.automaticexpense.tracker.domain.BillReminderStatus;
import com.automaticexpense.tracker.domain.BillStatement;
import com.automaticexpense.tracker.domain.Money;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

class BillReminderWorkerTest {

    @Test
    void shouldDeliverTheDueDateReminderOnceAndPersistItsDelivery() {
        BillStatement bill = new BillStatement(
            "bill-worker-1",
            new AccountId("acc-card-1"),
            "HDFC Credit Card",
            Money.of("15000.00", "INR"),
            Money.of("1000.00", "INR"),
            LocalDate.of(2026, 8, 15),
            LocalDate.of(2026, 9, 10)
        );
        InMemoryBills bills = new InMemoryBills(bill);
        InMemoryReminders reminders = new InMemoryReminders();
        RecordingPublisher publisher = new RecordingPublisher();
        BillReminderWorker worker = new BillReminderWorker(
            new BillReminderScheduler(bills, reminders), bills, publisher
        );

        worker.handleRequest(Map.of("date", "2026-09-10"), null);
        worker.handleRequest(Map.of("date", "2026-09-10"), null);

        assertThat(publisher.delivered).containsExactly("bill-worker-1#DUE_DATE");
        assertThat(reminders.byId("bill-worker-1#DUE_DATE").status()).isEqualTo(BillReminderStatus.DELIVERED);
    }

    private static final class InMemoryBills implements BillRepository {
        private final BillStatement bill;

        private InMemoryBills(BillStatement bill) {
            this.bill = bill;
        }

        @Override public void save(BillStatement billStatement) {}
        @Override public Optional<BillStatement> findBillById(String billId) {
            return bill.id().equals(billId) ? Optional.of(bill) : Optional.empty();
        }
        @Override public List<BillStatement> findPendingBills() {
            return bill.isPaid() ? List.of() : List.of(bill);
        }
        @Override public List<BillStatement> findAllBills() {
            return List.of(bill);
        }
    }

    private static final class InMemoryReminders implements BillReminderRepository {
        private final Map<String, BillReminder> reminders = new LinkedHashMap<>();

        @Override public boolean scheduleIfAbsent(BillReminder reminder) {
            return reminders.putIfAbsent(reminder.id(), reminder) == null;
        }
        @Override public List<BillReminder> findScheduledFor(LocalDate date) {
            return reminders.values().stream()
                .filter(reminder -> reminder.scheduledFor().equals(date))
                .filter(reminder -> reminder.status() == BillReminderStatus.SCHEDULED)
                .toList();
        }
        @Override public Optional<BillReminder> claim(String reminderId) {
            BillReminder reminder = reminders.get(reminderId);
            if (reminder == null || reminder.status() != BillReminderStatus.SCHEDULED) {
                return Optional.empty();
            }
            BillReminder claimed = reminder.withStatus(BillReminderStatus.CLAIMED);
            reminders.put(reminderId, claimed);
            return Optional.of(claimed);
        }
        @Override public void markDelivered(String reminderId) {
            reminders.computeIfPresent(reminderId, (id, reminder) -> reminder.withStatus(BillReminderStatus.DELIVERED));
        }
        @Override public void releaseClaim(String reminderId) {
            reminders.computeIfPresent(reminderId, (id, reminder) -> reminder.withStatus(BillReminderStatus.SCHEDULED));
        }
        @Override public void cancel(String reminderId) {
            reminders.computeIfPresent(reminderId, (id, reminder) -> reminder.withStatus(BillReminderStatus.CANCELLED));
        }
        BillReminder byId(String reminderId) {
            return reminders.get(reminderId);
        }
    }

    private static final class RecordingPublisher implements BillReminderNotificationPort {
        private final List<String> delivered = new ArrayList<>();

        @Override
        public void send(BillReminder reminder, BillStatement bill) {
            delivered.add(reminder.id());
        }
    }
}
