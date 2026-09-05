package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.BillReminder;
import com.automaticexpense.tracker.domain.BillStatement;

public interface BillReminderNotificationPort {
    void send(BillReminder reminder, BillStatement bill);
}
