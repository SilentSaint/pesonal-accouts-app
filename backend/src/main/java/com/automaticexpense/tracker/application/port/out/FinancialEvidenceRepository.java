package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.FinancialEvidencePage;
import com.automaticexpense.tracker.domain.FinancialEvidenceQuery;

public interface FinancialEvidenceRepository {
    FinancialEvidencePage load(FinancialEvidenceQuery query);
}
