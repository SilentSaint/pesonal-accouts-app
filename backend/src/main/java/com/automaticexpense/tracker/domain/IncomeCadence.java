package com.automaticexpense.tracker.domain;

public enum IncomeCadence {
    ONCE,
    WEEKLY,
    BIWEEKLY,
    MONTHLY,
    QUARTERLY,
    YEARLY;

    public boolean isRecurring() {
        return this != ONCE;
    }
}
