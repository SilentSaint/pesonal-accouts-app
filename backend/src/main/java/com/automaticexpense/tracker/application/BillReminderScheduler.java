package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.out.BillReminderRepository;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.domain.BillReminder;
import com.automaticexpense.tracker.domain.BillReminderTiming;
import com.automaticexpense.tracker.domain.BillStatement;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

public final class BillReminderScheduler {
    private final BillRepository billRepository;
    private final BillReminderRepository reminderRepository;

    public BillReminderScheduler(BillRepository billRepository, BillReminderRepository reminderRepository) {
        this.billRepository = Objects.requireNonNull(billRepository, "billRepository cannot be null");
        this.reminderRepository = Objects.requireNonNull(reminderRepository, "reminderRepository cannot be null");
    }

    public List<BillReminder> schedulePendingBillReminders() {
        List<BillReminder> scheduled = new ArrayList<>();
        for (BillStatement bill : billRepository.findPendingBills()) {
            for (BillReminderTiming timing : BillReminderTiming.values()) {
                BillReminder reminder = BillReminder.scheduledFor(bill, timing);
                if (reminderRepository.scheduleIfAbsent(reminder)) {
                    scheduled.add(reminder);
                }
            }
        }
        return List.copyOf(scheduled);
    }

    public List<BillReminder> claimDueReminders(LocalDate today) {
        Objects.requireNonNull(today, "today cannot be null");
        refreshOverdueBills(today);
        schedulePendingBillReminders();

        List<BillReminder> claimed = new ArrayList<>();
        for (BillReminder reminder : reminderRepository.findScheduledFor(today)) {
            BillStatement bill = billRepository.findBillById(reminder.billId()).orElse(null);
            if (bill == null || bill.isPaid()) {
                reminderRepository.cancel(reminder.id());
                continue;
            }
            reminderRepository.claim(reminder.id()).ifPresent(claimed::add);
        }
        return List.copyOf(claimed);
    }

    public void markDelivered(BillReminder reminder) {
        reminderRepository.markDelivered(reminder.id());
    }

    public void releaseClaim(BillReminder reminder) {
        reminderRepository.releaseClaim(reminder.id());
    }

    private void refreshOverdueBills(LocalDate today) {
        for (BillStatement bill : billRepository.findPendingBills()) {
            if (bill.updateLifecycleStatus(today)) {
                billRepository.save(bill);
            }
        }
    }
}
