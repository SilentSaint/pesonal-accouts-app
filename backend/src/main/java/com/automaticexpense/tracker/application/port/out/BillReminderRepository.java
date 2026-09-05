package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.BillReminder;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface BillReminderRepository {
    boolean scheduleIfAbsent(BillReminder reminder);

    default List<BillReminder> findScheduledFor(LocalDate date) {
        return List.of();
    }

    default Optional<BillReminder> claim(String reminderId) {
        return Optional.empty();
    }

    default void markDelivered(String reminderId) {
    }

    default void releaseClaim(String reminderId) {
    }

    default void cancel(String reminderId) {
    }
}
