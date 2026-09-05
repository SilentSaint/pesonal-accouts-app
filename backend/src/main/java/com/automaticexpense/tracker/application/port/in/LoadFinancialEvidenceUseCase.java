package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.FinancialEvidencePage;
import com.automaticexpense.tracker.domain.FinancialEvidenceQuery;
import com.automaticexpense.tracker.domain.IntelligenceResult;

public interface LoadFinancialEvidenceUseCase {
    IntelligenceResult<FinancialEvidencePage> load(FinancialEvidenceQuery query);
}
