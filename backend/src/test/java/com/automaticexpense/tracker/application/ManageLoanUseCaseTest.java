package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ManageLoanUseCase;
import com.automaticexpense.tracker.application.port.out.LoanRepository;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ManageLoanUseCaseTest {

    private InMemoryLoanRepository loanRepository;
    private ManageLoanUseCase loanUseCase;

    @BeforeEach
    void setUp() {
        loanRepository = new InMemoryLoanRepository();
        loanUseCase = new LoanService(loanRepository);
    }

    @Test
    void shouldRegisterNewLoanAccount() {
        LoanAccount loan = loanUseCase.registerLoan(
            "SBI Car Loan",
            "State Bank of India",
            Money.of("800000.00", "INR"),
            Money.of("18500.00", "INR"),
            9.25,
            60,
            LocalDate.of(2026, 9, 10)
        );

        assertThat(loan.id()).isNotBlank();
        assertThat(loan.loanName()).isEqualTo("SBI Car Loan");
        assertThat(loan.principalAmount()).isEqualTo(Money.of("800000.00", "INR"));
        assertThat(loan.remainingInstallments()).isEqualTo(60);
        assertThat(loan.status()).isEqualTo(LoanStatus.ACTIVE);

        Optional<LoanAccount> retrieved = loanRepository.findLoanById(loan.id());
        assertThat(retrieved).isPresent();
    }

    @Test
    void shouldRecordManualEmiPayment() {
        LoanAccount loan = loanUseCase.registerLoan(
            "HDFC Personal Loan",
            "HDFC Bank",
            Money.of("200000.00", "INR"),
            Money.of("10000.00", "INR"),
            12.0,
            24,
            LocalDate.of(2026, 9, 5)
        );

        LoanAccount updated = loanUseCase.recordEmiPayment(loan.id(), Money.of("10000.00", "INR"));

        assertThat(updated.completedInstallments()).isEqualTo(1);
        assertThat(updated.remainingInstallments()).isEqualTo(23);
        assertThat(updated.nextDueDate()).isEqualTo(LocalDate.of(2026, 10, 5));
    }

    @Test
    void shouldAutoMatchEmiDebitTransactionToActiveLoan() {
        LoanAccount loan = loanUseCase.registerLoan(
            "Axis Home Loan",
            "Axis Bank",
            Money.of("3500000.00", "INR"),
            Money.of("32500.00", "INR"),
            8.75,
            180,
            LocalDate.of(2026, 9, 5)
        );

        // Transaction representing monthly bank auto-debit for EMI
        Transaction emiTx = new Transaction(
            new TransactionId("tx-emi-debit"),
            Money.of("32500.00", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 9, 5, 10, 0),
            "Axis Bank Loan EMI",
            new AccountId("acc-salary"),
            "LOAN_EMI",
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            Money.of("32500.00", "INR")
        );

        Optional<LoanAccount> matched = loanUseCase.matchAndApplyEmiDebit(emiTx);

        assertThat(matched).isPresent();
        assertThat(matched.get().id()).isEqualTo(loan.id());
        assertThat(matched.get().completedInstallments()).isEqualTo(1);
        assertThat(matched.get().nextDueDate()).isEqualTo(LocalDate.of(2026, 10, 5));
    }

    private static class InMemoryLoanRepository implements LoanRepository {
        private final Map<String, LoanAccount> store = new HashMap<>();

        @Override
        public void save(LoanAccount loanAccount) {
            store.put(loanAccount.id(), loanAccount);
        }

        @Override
        public Optional<LoanAccount> findLoanById(String loanId) {
            return Optional.ofNullable(store.get(loanId));
        }

        @Override
        public List<LoanAccount> findAllActive() {
            return store.values().stream().filter(l -> !l.isClosed()).toList();
        }

        @Override
        public List<LoanAccount> findAllLoans() {
            return new ArrayList<>(store.values());
        }
    }
}
