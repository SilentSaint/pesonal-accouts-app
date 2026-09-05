package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IncomeCadence;
import com.automaticexpense.tracker.domain.IncomeSource;
import com.automaticexpense.tracker.domain.IncomeSourceType;
import com.automaticexpense.tracker.domain.IncomeSuggestion;
import com.automaticexpense.tracker.domain.IncomeSummary;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.TransactionId;

import java.time.LocalDate;
import java.util.List;
import java.util.Set;

public interface ManageIncomeSourceUseCase {
    IncomeSource createIncomeSource(
        String name,
        IncomeSourceType type,
        Money amount,
        IncomeCadence cadence,
        LocalDate effectiveFrom,
        LocalDate effectiveTo,
        AccountId linkedAccountId,
        Set<TransactionId> sourceTransactionIds
    );

    IncomeSource updateEffectiveDates(String incomeSourceId, LocalDate effectiveFrom, LocalDate effectiveTo);

    List<IncomeSuggestion> detectIncomeSuggestions();

    List<IncomeSuggestion> getUnconfirmedSuggestions();

    IncomeSource confirmSuggestion(String incomeSourceId);

    IncomeSource rejectSuggestion(String incomeSourceId);

    List<IncomeSource> getConfirmedIncomeSources();

    IncomeSummary summarize(LocalDate periodStart, LocalDate periodEnd, LocalDate asOf, String currency);
}
