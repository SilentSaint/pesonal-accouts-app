package com.automaticexpense.tracker.domain;

import java.time.LocalDate;

public enum RecurringCommitmentCadence {
    WEEKLY,
    BIWEEKLY,
    MONTHLY,
    QUARTERLY,
    YEARLY;

    public LocalDate nextAfter(LocalDate date) {
        return switch (this) {
            case WEEKLY -> date.plusWeeks(1);
            case BIWEEKLY -> date.plusWeeks(2);
            case MONTHLY -> date.plusMonths(1);
            case QUARTERLY -> date.plusMonths(3);
            case YEARLY -> date.plusYears(1);
        };
    }

    public int lateToleranceDays() {
        return switch (this) {
            case WEEKLY -> 2;
            case BIWEEKLY -> 3;
            case MONTHLY -> 7;
            case QUARTERLY -> 14;
            case YEARLY -> 35;
        };
    }
}
