package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.ExpectedAmountRange;
import com.automaticexpense.tracker.domain.RecurringCommitment;
import com.automaticexpense.tracker.domain.RecurringCommitmentCadence;
import com.automaticexpense.tracker.domain.RecurringCommitmentClassification;
import com.automaticexpense.tracker.domain.RecurringCommitmentSummary;

import java.time.LocalDate;
import java.util.List;

public interface ManageRecurringCommitmentsUseCase {
    List<RecurringCommitment> detectCandidates(LocalDate asOf);

    RecurringCommitment confirm(String commitmentId);

    RecurringCommitment create(
        String name,
        RecurringCommitmentClassification classification,
        RecurringCommitmentCadence cadence,
        ExpectedAmountRange expectedAmountRange,
        LocalDate nextPaymentDate
    );

    RecurringCommitment correct(
        String commitmentId,
        String name,
        RecurringCommitmentClassification classification,
        RecurringCommitmentCadence cadence,
        ExpectedAmountRange expectedAmountRange,
        LocalDate nextPaymentDate
    );

    RecurringCommitment ignore(String commitmentId);

    RecurringCommitment cancel(String commitmentId);

    RecurringCommitment restore(String commitmentId);

    List<RecurringCommitment> list(LocalDate asOf);

    RecurringCommitmentSummary summarizeFixedCosts(LocalDate asOf, String currency);
}
