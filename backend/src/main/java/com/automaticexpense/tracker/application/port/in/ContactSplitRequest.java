package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.Money;
import java.util.Objects;

public record ContactSplitRequest(String contactName, Money shareAmount, String note) {
    public ContactSplitRequest {
        Objects.requireNonNull(contactName, "contactName cannot be null");
        Objects.requireNonNull(shareAmount, "shareAmount cannot be null");
    }
}
