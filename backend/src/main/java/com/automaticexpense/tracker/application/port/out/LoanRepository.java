package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.LoanAccount;

import java.util.List;
import java.util.Optional;

public interface LoanRepository {
    void save(LoanAccount loanAccount);
    Optional<LoanAccount> findLoanById(String loanId);
    List<LoanAccount> findAllActive();
    List<LoanAccount> findAllLoans();
}
