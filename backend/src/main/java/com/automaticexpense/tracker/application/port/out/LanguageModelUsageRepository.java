package com.automaticexpense.tracker.application.port.out;

import java.time.YearMonth;

public interface LanguageModelUsageRepository {
    boolean reserve(String provider, YearMonth month, int maximumRequests);
}
