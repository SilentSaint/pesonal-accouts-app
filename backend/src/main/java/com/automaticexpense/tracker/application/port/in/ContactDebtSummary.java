package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.Money;
import java.util.Objects;

public record ContactDebtSummary(
    String contactName,
    Money netBalance, // positive = user is owed money (+), negative = user owes money (-)
    Money totalLent,
    Money totalBorrowed,
    int activeDebtCount
) {
    public ContactDebtSummary {
        Objects.requireNonNull(contactName, "contactName cannot be null");
        Objects.requireNonNull(netBalance, "netBalance cannot be null");
        Objects.requireNonNull(totalLent, "totalLent cannot be null");
        Objects.requireNonNull(totalBorrowed, "totalBorrowed cannot be null");
    }
}
