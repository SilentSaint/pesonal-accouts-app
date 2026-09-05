package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.LanguageModelUsage;

public interface LanguageModelUsageTelemetryPort {
    void record(LanguageModelUsage usage);
}
