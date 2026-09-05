package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.util.Objects;

public record BillReminder(
    String id,
    String billId,
    BillReminderTiming timing,
    LocalDate scheduledFor,
    BillReminderStatus status
) {
    public BillReminder {
        Objects.requireNonNull(id, "id cannot be null");
        Objects.requireNonNull(billId, "billId cannot be null");
        Objects.requireNonNull(timing, "timing cannot be null");
        Objects.requireNonNull(scheduledFor, "scheduledFor cannot be null");
        Objects.requireNonNull(status, "status cannot be null");
    }

    public static BillReminder scheduledFor(BillStatement bill, BillReminderTiming timing) {
        return new BillReminder(
            bill.id() + "#" + timing.name(),
            bill.id(),
            timing,
            bill.dueDate().minusDays(timing.daysBeforeDue()),
            BillReminderStatus.SCHEDULED
        );
    }

    public BillReminder withStatus(BillReminderStatus updatedStatus) {
        return new BillReminder(id, billId, timing, scheduledFor, updatedStatus);
    }
}
