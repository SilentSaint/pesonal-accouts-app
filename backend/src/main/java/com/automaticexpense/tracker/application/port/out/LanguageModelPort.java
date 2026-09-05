package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.LanguageModelPlanningPrompt;
import com.automaticexpense.tracker.domain.LanguageModelPlanningResponse;

public interface LanguageModelPort {
    LanguageModelPlanningResponse plan(LanguageModelPlanningPrompt prompt);
}
