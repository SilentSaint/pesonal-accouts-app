package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.out.BillReminderRepository;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.BillReminder;
import com.automaticexpense.tracker.domain.BillStatement;
import com.automaticexpense.tracker.domain.Money;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

class BillReminderSchedulerTest {

    @Test
    void shouldPersistExactlyOneReminderForEachRequiredDueDate() {
        BillStatement bill = new BillStatement(
            "bill-reminder-1",
            new AccountId("acc-card-1"),
            "HDFC Credit Card",
            Money.of("15000.00", "INR"),
            Money.of("1000.00", "INR"),
            LocalDate.of(2026, 8, 15),
            LocalDate.of(2026, 9, 10)
        );
        InMemoryBillRepository bills = new InMemoryBillRepository(bill);
        InMemoryBillReminderRepository reminders = new InMemoryBillReminderRepository();
        BillReminderScheduler scheduler = new BillReminderScheduler(bills, reminders);

        assertThat(scheduler.schedulePendingBillReminders()).hasSize(3);
        assertThat(scheduler.schedulePendingBillReminders()).isEmpty();
        assertThat(reminders.scheduledFor(LocalDate.of(2026, 9, 5))).singleElement()
            .extracting(BillReminder::scheduledFor).isEqualTo(LocalDate.of(2026, 9, 5));
        assertThat(reminders.scheduledFor(LocalDate.of(2026, 9, 8))).singleElement()
            .extracting(BillReminder::scheduledFor).isEqualTo(LocalDate.of(2026, 9, 8));
        assertThat(reminders.scheduledFor(LocalDate.of(2026, 9, 10))).singleElement()
            .extracting(BillReminder::scheduledFor).isEqualTo(LocalDate.of(2026, 9, 10));
    }

    private static final class InMemoryBillRepository implements BillRepository {
        private final BillStatement bill;

        private InMemoryBillRepository(BillStatement bill) {
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

    private static final class InMemoryBillReminderRepository implements BillReminderRepository {
        private final List<BillReminder> reminders = new ArrayList<>();

        @Override
        public boolean scheduleIfAbsent(BillReminder reminder) {
            if (reminders.stream().anyMatch(existing -> existing.id().equals(reminder.id()))) {
                return false;
            }
            reminders.add(reminder);
            return true;
        }

        List<BillReminder> scheduledFor(LocalDate date) {
            return reminders.stream().filter(reminder -> reminder.scheduledFor().equals(date)).toList();
        }
    }
}
