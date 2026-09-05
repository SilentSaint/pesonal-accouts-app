package com.automaticexpense.tracker.domain;

public enum BillReminderTiming {
    FIVE_DAYS_BEFORE(5),
    TWO_DAYS_BEFORE(2),
    DUE_DATE(0);

    private final int daysBeforeDue;

    BillReminderTiming(int daysBeforeDue) {
        this.daysBeforeDue = daysBeforeDue;
    }

    public int daysBeforeDue() {
        return daysBeforeDue;
    }
}
