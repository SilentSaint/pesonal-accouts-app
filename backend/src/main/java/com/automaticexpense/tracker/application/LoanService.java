package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ManageLoanUseCase;
import com.automaticexpense.tracker.application.port.out.LoanRepository;
import com.automaticexpense.tracker.domain.LoanAccount;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.Transaction;

import java.time.LocalDate;
import java.util.*;

public class LoanService implements ManageLoanUseCase {

    private final LoanRepository loanRepository;

    public LoanService(LoanRepository loanRepository) {
        this.loanRepository = Objects.requireNonNull(loanRepository, "loanRepository cannot be null");
    }

    @Override
    public LoanAccount registerLoan(
        String loanName,
        String lenderName,
        Money principalAmount,
        Money emiAmount,
        double interestRatePercent,
        int totalInstallments,
        LocalDate startDate
    ) {
        Objects.requireNonNull(lenderName, "lenderName cannot be null");
        Objects.requireNonNull(principalAmount, "principalAmount cannot be null");
        Objects.requireNonNull(emiAmount, "emiAmount cannot be null");

        LoanAccount loan = new LoanAccount(
            UUID.randomUUID().toString(),
            loanName,
            lenderName,
            principalAmount,
            emiAmount,
            interestRatePercent,
            totalInstallments,
            0,
            startDate != null ? startDate : LocalDate.now().plusMonths(1)
        );

        loanRepository.save(loan);
        return loan;
    }

    @Override
    public LoanAccount recordEmiPayment(String loanId, Money paymentAmount) {
        Objects.requireNonNull(loanId, "loanId cannot be null");
        Objects.requireNonNull(paymentAmount, "paymentAmount cannot be null");

        LoanAccount loan = loanRepository.findLoanById(loanId)
            .orElseThrow(() -> new IllegalArgumentException("Loan account not found: " + loanId));

        loan.recordEmiPayment(paymentAmount);
        loanRepository.save(loan);
        return loan;
    }

    @Override
    public Optional<LoanAccount> matchAndApplyEmiDebit(Transaction transaction) {
        if (transaction == null || transaction.type() != com.automaticexpense.tracker.domain.TransactionType.DEBIT) {
            return Optional.empty();
        }

        List<LoanAccount> activeLoans = loanRepository.findAllActive();
        String merchant = transaction.merchantName().toLowerCase();

        for (LoanAccount loan : activeLoans) {
            boolean matchesLender = merchant.contains(loan.lenderName().toLowerCase())
                || merchant.contains("loan")
                || merchant.contains("emi");
            boolean matchesAmount = loan.emiAmount().amount().compareTo(transaction.amount().amount()) == 0;

            if (matchesLender && matchesAmount) {
                loan.recordEmiPayment(transaction.amount());
                loanRepository.save(loan);
                return Optional.of(loan);
            }
        }

        return Optional.empty();
    }

    @Override
    public Optional<LoanAccount> getLoanById(String loanId) {
        return loanRepository.findLoanById(loanId);
    }

    @Override
    public List<LoanAccount> getActiveLoans() {
        return loanRepository.findAllActive();
    }

    @Override
    public List<LoanAccount> getAllLoans() {
        return loanRepository.findAllLoans();
    }
}
