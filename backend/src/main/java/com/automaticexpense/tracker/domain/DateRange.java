package com.automaticexpense.tracker.domain;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.Objects;

public record DateRange(LocalDate start, LocalDate end) {
    public DateRange {
        Objects.requireNonNull(start, "start cannot be null");
        Objects.requireNonNull(end, "end cannot be null");
        if (end.isBefore(start)) {
            throw new IllegalArgumentException("end cannot be before start");
        }
    }

    public boolean contains(LocalDate date) {
        return !date.isBefore(start) && !date.isAfter(end);
    }

    public DateRange previousEquivalent() {
        long days = ChronoUnit.DAYS.between(start, end) + 1;
        return new DateRange(start.minusDays(days), start.minusDays(1));
    }

    public DateRange yearEarlier() {
        return new DateRange(start.minusYears(1), end.minusYears(1));
    }
}
