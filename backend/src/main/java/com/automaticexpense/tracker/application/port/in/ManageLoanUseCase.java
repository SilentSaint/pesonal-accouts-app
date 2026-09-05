package com.automaticexpense.tracker.application.port.in;

import com.automaticexpense.tracker.domain.LoanAccount;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.Transaction;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface ManageLoanUseCase {
    LoanAccount registerLoan(
        String loanName,
        String lenderName,
        Money principalAmount,
        Money emiAmount,
        double interestRatePercent,
        int totalInstallments,
        LocalDate startDate
    );

    LoanAccount recordEmiPayment(String loanId, Money paymentAmount);

    Optional<LoanAccount> matchAndApplyEmiDebit(Transaction transaction);

    Optional<LoanAccount> getLoanById(String loanId);

    List<LoanAccount> getActiveLoans();

    List<LoanAccount> getAllLoans();
}
