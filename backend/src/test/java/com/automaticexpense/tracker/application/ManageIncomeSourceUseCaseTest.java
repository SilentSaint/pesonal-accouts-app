package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ManageIncomeSourceUseCase;
import com.automaticexpense.tracker.application.port.out.IncomeSourceRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IncomeCadence;
import com.automaticexpense.tracker.domain.IncomeConfirmationStatus;
import com.automaticexpense.tracker.domain.IncomeSource;
import com.automaticexpense.tracker.domain.IncomeSourceType;
import com.automaticexpense.tracker.domain.IncomeSummary;
import com.automaticexpense.tracker.domain.IngestionSource;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.TransactionType;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

class ManageIncomeSourceUseCaseTest {

    @Test
    void recognizesOnlyAConfirmedRecurringCreditSuggestionAsIncome() {
        InMemoryTransactions transactions = new InMemoryTransactions();
        Transaction januarySalary = credit("salary-jan", "Acme Payroll", "75000.00", LocalDateTime.of(2026, 1, 31, 9, 0));
        transactions.save(januarySalary);
        transactions.save(credit("salary-feb", "Acme Payroll", "75000.00", LocalDateTime.of(2026, 2, 28, 9, 0)));
        transactions.save(credit("salary-mar", "Acme Payroll", "75000.00", LocalDateTime.of(2026, 3, 31, 9, 0)));
        transactions.save(credit("refund-jan", "Merchant refund", "500.00", LocalDateTime.of(2026, 1, 12, 9, 0)));
        transactions.save(credit("refund-feb", "Merchant refund", "500.00", LocalDateTime.of(2026, 2, 12, 9, 0)));
        transactions.save(credit("refund-mar", "Merchant refund", "500.00", LocalDateTime.of(2026, 3, 12, 9, 0)));
        transactions.save(credit("loan-jan", "Loan proceeds", "200000.00", LocalDateTime.of(2026, 1, 15, 9, 0)));
        transactions.save(credit("loan-feb", "Loan proceeds", "200000.00", LocalDateTime.of(2026, 2, 15, 9, 0)));
        transactions.save(credit("loan-mar", "Loan proceeds", "200000.00", LocalDateTime.of(2026, 3, 15, 9, 0)));
        transactions.save(credit("transfer-jan", "Internal transfer", "50000.00", LocalDateTime.of(2026, 1, 5, 9, 0)));
        transactions.save(credit("transfer-feb", "Internal transfer", "50000.00", LocalDateTime.of(2026, 2, 5, 9, 0)));
        transactions.save(credit("transfer-mar", "Internal transfer", "50000.00", LocalDateTime.of(2026, 3, 5, 9, 0)));
        transactions.save(credit("reversal-jan", "Card reversal", "1000.00", LocalDateTime.of(2026, 1, 18, 9, 0)));
        transactions.save(credit("reversal-feb", "Card reversal", "1000.00", LocalDateTime.of(2026, 2, 18, 9, 0)));
        transactions.save(credit("reversal-mar", "Card reversal", "1000.00", LocalDateTime.of(2026, 3, 18, 9, 0)));

        ManageIncomeSourceUseCase incomes = new IncomeSourceService(new InMemoryIncomeSources(), transactions);

        assertThat(incomes.detectIncomeSuggestions())
            .singleElement()
            .satisfies(suggestion -> {
                assertThat(suggestion.source().name()).isEqualTo("Acme Payroll");
                assertThat(suggestion.source().cadence()).isEqualTo(IncomeCadence.MONTHLY);
                assertThat(suggestion.source().sourceTransactionIds())
                    .containsExactlyInAnyOrder(
                        new TransactionId("salary-jan"),
                        new TransactionId("salary-feb"),
                        new TransactionId("salary-mar")
                    );
                assertThat(suggestion.confidence()).isGreaterThanOrEqualTo(0.9);
            });

        IncomeSummary beforeConfirmation = incomes.summarize(
            LocalDate.of(2026, 3, 1), LocalDate.of(2026, 3, 31), LocalDate.of(2026, 3, 31), "INR"
        );
        assertThat(beforeConfirmation.observed()).isEqualTo(Money.zero("INR"));
        assertThat(beforeConfirmation.expected()).isEqualTo(Money.zero("INR"));
        assertThat(beforeConfirmation.uncertain()).isEqualTo(Money.of("75000.00", "INR"));

        String suggestionId = incomes.getUnconfirmedSuggestions().getFirst().source().id();
        IncomeSource confirmed = incomes.confirmSuggestion(suggestionId);
        IncomeSource confirmedAgain = incomes.confirmSuggestion(suggestionId);
        IncomeSummary afterConfirmation = incomes.summarize(
            LocalDate.of(2026, 3, 1), LocalDate.of(2026, 3, 31), LocalDate.of(2026, 3, 31), "INR"
        );

        assertThat(confirmedAgain).isEqualTo(confirmed);
        assertThat(confirmed.confirmationStatus()).isEqualTo(IncomeConfirmationStatus.CONFIRMED);
        assertThat(transactions.findById(januarySalary.id())).contains(januarySalary);
        assertThat(afterConfirmation.observed()).isEqualTo(Money.of("75000.00", "INR"));
        assertThat(afterConfirmation.expected()).isEqualTo(Money.of("75000.00", "INR"));
        assertThat(afterConfirmation.uncertain()).isEqualTo(Money.zero("INR"));
    }

    @Test
    void supportsConfirmedFixedVariableOneTimeAndRecurringSourcesAndRejectsSuggestionsIdempotently() {
        InMemoryIncomeSources sources = new InMemoryIncomeSources();
        ManageIncomeSourceUseCase incomes = new IncomeSourceService(sources, new InMemoryTransactions());
        AccountId account = new AccountId("income-account");

        IncomeSource fixed = incomes.createIncomeSource(
            "Salary", IncomeSourceType.FIXED, Money.of("75000.00", "INR"), IncomeCadence.MONTHLY,
            LocalDate.of(2026, 1, 1), null, account, java.util.Set.of()
        );
        IncomeSource variable = incomes.createIncomeSource(
            "Freelance", IncomeSourceType.VARIABLE, Money.of("12000.00", "INR"), IncomeCadence.MONTHLY,
            LocalDate.of(2026, 1, 1), null, account, java.util.Set.of()
        );
        IncomeSource oneTime = incomes.createIncomeSource(
            "Bonus", IncomeSourceType.ONE_TIME, Money.of("5000.00", "INR"), IncomeCadence.ONCE,
            LocalDate.of(2026, 3, 15), LocalDate.of(2026, 3, 15), account, java.util.Set.of()
        );
        IncomeSource recurring = incomes.createIncomeSource(
            "Rental income", IncomeSourceType.RECURRING, Money.of("20000.00", "INR"), IncomeCadence.MONTHLY,
            LocalDate.of(2026, 1, 10), null, account, java.util.Set.of()
        );
        IncomeSource pending = IncomeSource.suggested(
            "candidate-1", "Possible payroll", IncomeSourceType.FIXED, Money.of("70000.00", "INR"),
            IncomeCadence.MONTHLY, LocalDate.of(2026, 1, 31), null, account, java.util.Set.of(),
            "candidate-payroll"
        );
        sources.save(pending);

        IncomeSource edited = incomes.updateEffectiveDates(fixed.id(), LocalDate.of(2026, 2, 1), null);
        IncomeSource rejected = incomes.rejectSuggestion(pending.id());

        assertThat(incomes.getConfirmedIncomeSources())
            .extracting(IncomeSource::type)
            .containsExactlyInAnyOrder(
                IncomeSourceType.FIXED, IncomeSourceType.VARIABLE,
                IncomeSourceType.ONE_TIME, IncomeSourceType.RECURRING
            );
        assertThat(edited.effectiveFrom()).isEqualTo(LocalDate.of(2026, 2, 1));
        assertThat(incomes.rejectSuggestion(pending.id())).isEqualTo(rejected);
        assertThat(rejected.confirmationStatus()).isEqualTo(IncomeConfirmationStatus.REJECTED);
        assertThat(incomes.getUnconfirmedSuggestions()).isEmpty();
        assertThat(oneTime.isActiveOn(LocalDate.of(2026, 3, 15))).isTrue();
        assertThat(recurring.isConfirmed()).isTrue();
        assertThat(variable.isConfirmed()).isTrue();
    }

    @Test
    void excludesEvidenceAndScheduledIncomeThatOccursAfterTheRequestedAsOfDate() {
        InMemoryTransactions transactions = new InMemoryTransactions();
        Transaction februarySalary = credit(
            "salary-feb", "Acme Payroll", "75000.00", LocalDateTime.of(2026, 2, 28, 9, 0)
        );
        Transaction marchSalary = credit(
            "salary-mar", "Acme Payroll", "75000.00", LocalDateTime.of(2026, 3, 31, 9, 0)
        );
        transactions.save(februarySalary);
        transactions.save(marchSalary);
        InMemoryIncomeSources sources = new InMemoryIncomeSources();
        sources.save(IncomeSource.confirmed(
            "acme-income", "Acme Payroll", IncomeSourceType.FIXED, Money.of("75000.00", "INR"),
            IncomeCadence.MONTHLY, LocalDate.of(2026, 2, 28), null, new AccountId("salary-account"),
            java.util.Set.of(februarySalary.id(), marchSalary.id())
        ));
        ManageIncomeSourceUseCase incomes = new IncomeSourceService(sources, transactions);

        IncomeSummary summary = incomes.summarize(
            LocalDate.of(2026, 2, 1), LocalDate.of(2026, 3, 31), LocalDate.of(2026, 2, 28), "INR"
        );

        assertThat(summary.observed()).isEqualTo(Money.of("75000.00", "INR"));
        assertThat(summary.expected()).isEqualTo(Money.of("75000.00", "INR"));
    }

    @Test
    void reportsPendingRecurringIncomeForEveryExpectedOccurrenceBeforeAsOf() {
        InMemoryTransactions transactions = new InMemoryTransactions();
        Transaction januarySalary = credit(
            "salary-jan", "Acme Payroll", "75000.00", LocalDateTime.of(2026, 1, 31, 9, 0)
        );
        transactions.save(januarySalary);
        InMemoryIncomeSources sources = new InMemoryIncomeSources();
        sources.save(IncomeSource.suggested(
            "candidate-payroll", "Acme Payroll", IncomeSourceType.FIXED, Money.of("75000.00", "INR"),
            IncomeCadence.MONTHLY, LocalDate.of(2026, 1, 31), null, new AccountId("salary-account"),
            java.util.Set.of(januarySalary.id()), "acme-payroll-monthly"
        ));

        IncomeSummary summary = new IncomeSourceService(sources, transactions).summarize(
            LocalDate.of(2026, 1, 1), LocalDate.of(2026, 3, 31), LocalDate.of(2026, 3, 31), "INR"
        );

        assertThat(summary.uncertain()).isEqualTo(Money.of("225000.00", "INR"));
        assertThat(summary.unconfirmedSuggestionCount()).isEqualTo(1);
    }

    @Test
    void neverOverwritesAConfirmedSuggestionWhenRecurringDetectionRefreshesIt() {
        InMemoryTransactions transactions = new InMemoryTransactions();
        transactions.save(credit(
            "salary-jan", "Acme Payroll", "75000.00", LocalDateTime.of(2026, 1, 31, 9, 0)
        ));
        transactions.save(credit(
            "salary-feb", "Acme Payroll", "75000.00", LocalDateTime.of(2026, 2, 28, 9, 0)
        ));
        RaceIncomeSources sources = new RaceIncomeSources();
        sources.save(IncomeSource.suggested(
            "candidate-payroll", "Acme Payroll", IncomeSourceType.FIXED, Money.of("75000.00", "INR"),
            IncomeCadence.MONTHLY, LocalDate.of(2026, 1, 31), null, new AccountId("salary-account"),
            java.util.Set.of(new TransactionId("salary-jan")),
            "acme payroll|salary-account|INR|MONTHLY"
        ));

        List<?> suggestions = new IncomeSourceService(sources, transactions).detectIncomeSuggestions();

        assertThat(suggestions).isEmpty();
        assertThat(sources.findById("candidate-payroll").orElseThrow().confirmationStatus())
            .isEqualTo(IncomeConfirmationStatus.CONFIRMED);
    }

    private static Transaction credit(String id, String merchant, String amount, LocalDateTime timestamp) {
        return new Transaction(
            new TransactionId(id), Money.of(amount, "INR"), TransactionType.CREDIT, timestamp, merchant,
            new AccountId("salary-account"), null, IngestionSource.SMS, ReconciliationStatus.CONFIRMED,
            Money.of(amount, "INR")
        );
    }

    private static class InMemoryIncomeSources implements IncomeSourceRepository {
        protected final Map<String, IncomeSource> sources = new HashMap<>();

        @Override
        public void save(IncomeSource source) {
            sources.put(source.id(), source);
        }

        @Override
        public Optional<IncomeSource> findById(String incomeSourceId) {
            return Optional.ofNullable(sources.get(incomeSourceId));
        }

        @Override
        public Optional<IncomeSource> findBySuggestionKey(String suggestionKey) {
            return sources.values().stream().filter(source -> suggestionKey.equals(source.suggestionKey())).findFirst();
        }

        @Override
        public List<IncomeSource> findAll() {
            return new ArrayList<>(sources.values());
        }

        @Override
        public boolean replaceIfPending(IncomeSource source) {
            IncomeSource stored = sources.get(source.id());
            if (stored == null || stored.confirmationStatus() != IncomeConfirmationStatus.PENDING) {
                return false;
            }
            sources.put(source.id(), source);
            return true;
        }
    }

    private static final class RaceIncomeSources extends InMemoryIncomeSources {
        @Override
        public boolean replaceIfPending(IncomeSource source) {
            sources.put(source.id(), sources.get(source.id()).confirm());
            return false;
        }
    }

    private static final class InMemoryTransactions implements TransactionRepository {
        private final Map<TransactionId, Transaction> transactions = new HashMap<>();

        @Override
        public void save(Transaction transaction) {
            transactions.put(transaction.id(), transaction);
        }

        @Override
        public Optional<Transaction> findById(TransactionId id) {
            return Optional.ofNullable(transactions.get(id));
        }

        @Override
        public List<Transaction> findByAccountId(AccountId accountId) {
            return transactions.values().stream().filter(transaction -> transaction.accountId().equals(accountId)).toList();
        }

        @Override
        public List<Transaction> findByReconciliationStatus(ReconciliationStatus status) {
            return transactions.values().stream().filter(transaction -> transaction.reconciliationStatus() == status).toList();
        }

        @Override
        public List<Transaction> findByAccountIdAndWindow(AccountId accountId, LocalDateTime start, LocalDateTime end) {
            return transactions.values().stream()
                .filter(transaction -> transaction.accountId().equals(accountId))
                .filter(transaction -> !transaction.timestamp().isBefore(start) && !transaction.timestamp().isAfter(end))
                .toList();
        }

        @Override
        public List<Transaction> findAllTransactions() {
            return new ArrayList<>(transactions.values());
        }

        @Override
        public void delete(TransactionId id) {
            transactions.remove(id);
        }
    }
}
