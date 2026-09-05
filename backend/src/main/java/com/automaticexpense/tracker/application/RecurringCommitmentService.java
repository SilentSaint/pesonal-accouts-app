package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ManageRecurringCommitmentsUseCase;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.application.port.out.CardEmiRepository;
import com.automaticexpense.tracker.application.port.out.IncomeSourceRepository;
import com.automaticexpense.tracker.application.port.out.LoanRepository;
import com.automaticexpense.tracker.application.port.out.RecurringCommitmentRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.ExpectedAmountRange;
import com.automaticexpense.tracker.domain.BillStatement;
import com.automaticexpense.tracker.domain.CardEmiPlan;
import com.automaticexpense.tracker.domain.IncomeCadence;
import com.automaticexpense.tracker.domain.IncomeSource;
import com.automaticexpense.tracker.domain.IncomeSourceType;
import com.automaticexpense.tracker.domain.IntelligenceClassification;
import com.automaticexpense.tracker.domain.LoanAccount;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.RecurringCommitment;
import com.automaticexpense.tracker.domain.RecurringCommitmentCadence;
import com.automaticexpense.tracker.domain.RecurringCommitmentClassification;
import com.automaticexpense.tracker.domain.RecurringCommitmentOrigin;
import com.automaticexpense.tracker.domain.RecurringCommitmentState;
import com.automaticexpense.tracker.domain.RecurringCommitmentStatus;
import com.automaticexpense.tracker.domain.RecurringCommitmentSummary;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.TransactionType;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Optional;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.function.Predicate;
import java.util.stream.Collectors;

public final class RecurringCommitmentService implements ManageRecurringCommitmentsUseCase {
    private static final Predicate<String> EXCLUDED_DEBIT_TEXT = text -> {
        String normalized = text == null ? "" : text.toLowerCase();
        return normalized.contains("transfer") || normalized.contains("refund")
            || normalized.contains("reversal") || normalized.contains("cashback");
    };

    private final RecurringCommitmentRepository commitments;
    private final TransactionRepository transactions;
    private final BillRepository bills;
    private final LoanRepository loans;
    private final CardEmiRepository cardEmis;
    private final IncomeSourceRepository incomeSources;

    public RecurringCommitmentService(
        RecurringCommitmentRepository commitments, TransactionRepository transactions
    ) {
        this(commitments, transactions, null, null, null, null);
    }

    public RecurringCommitmentService(
        RecurringCommitmentRepository commitments,
        TransactionRepository transactions,
        BillRepository bills,
        LoanRepository loans,
        CardEmiRepository cardEmis,
        IncomeSourceRepository incomeSources
    ) {
        this.commitments = Objects.requireNonNull(commitments, "commitments cannot be null");
        this.transactions = Objects.requireNonNull(transactions, "transactions cannot be null");
        this.bills = bills;
        this.loans = loans;
        this.cardEmis = cardEmis;
        this.incomeSources = incomeSources;
    }

    @Override
    public List<RecurringCommitment> detectCandidates(LocalDate asOf) {
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Map<CandidateKey, List<Transaction>> groups = new HashMap<>();
        transactions.findAllTransactions().stream()
            .filter(this::isEligibleDebit)
            .filter(transaction -> !isReconciledToAuthority(transaction))
            .forEach(transaction -> groups.computeIfAbsent(
                new CandidateKey(normalize(transaction.merchantName()), transaction.accountId().value(),
                    transaction.amount().currency()),
                ignored -> new ArrayList<>()
            ).add(transaction));

        return groups.entrySet().stream()
            .map(entry -> candidate(entry.getKey(), entry.getValue(), asOf))
            .filter(Objects::nonNull)
            .map(this::saveOrReuse)
            .filter(commitment -> commitment.status() == RecurringCommitmentStatus.CANDIDATE)
            .toList();
    }

    @Override
    public RecurringCommitment confirm(String commitmentId) {
        RecurringCommitment confirmed = byId(commitmentId).confirm();
        commitments.save(confirmed);
        return confirmed;
    }

    @Override
    public RecurringCommitment create(
        String name,
        RecurringCommitmentClassification classification,
        RecurringCommitmentCadence cadence,
        ExpectedAmountRange expectedAmountRange,
        LocalDate nextPaymentDate
    ) {
        RecurringCommitment created = new RecurringCommitment(
            UUID.randomUUID().toString(), name, classification, cadence, expectedAmountRange, nextPaymentDate,
            1.0, java.util.Set.of(), RecurringCommitmentStatus.CONFIRMED,
            expectedAmountRange.isVariable() ? RecurringCommitmentState.VARIABLE_AMOUNT : RecurringCommitmentState.ON_TRACK,
            RecurringCommitmentOrigin.DETECTED, null, "manual:" + UUID.randomUUID()
        );
        commitments.save(created);
        return created;
    }

    @Override
    public RecurringCommitment correct(
        String commitmentId,
        String name,
        RecurringCommitmentClassification classification,
        RecurringCommitmentCadence cadence,
        ExpectedAmountRange expectedAmountRange,
        LocalDate nextPaymentDate
    ) {
        RecurringCommitment corrected = byId(commitmentId).corrected(
            name, classification, cadence, expectedAmountRange, nextPaymentDate
        );
        commitments.save(corrected);
        return corrected;
    }

    @Override
    public RecurringCommitment ignore(String commitmentId) {
        RecurringCommitment ignored = byId(commitmentId).ignore();
        commitments.save(ignored);
        return ignored;
    }

    @Override
    public RecurringCommitment cancel(String commitmentId) {
        RecurringCommitment cancelled = byId(commitmentId).cancel();
        commitments.save(cancelled);
        return cancelled;
    }

    @Override
    public RecurringCommitment restore(String commitmentId) {
        RecurringCommitment restored = byId(commitmentId).restore();
        commitments.save(restored);
        return restored;
    }

    @Override
    public List<RecurringCommitment> list(LocalDate asOf) {
        Objects.requireNonNull(asOf, "asOf cannot be null");
        List<RecurringCommitment> detected = commitments.findAll().stream()
            .filter(commitment -> commitment.status() != RecurringCommitmentStatus.IGNORED)
            .map(commitment -> commitment.asOf(asOf))
            .toList();
        List<RecurringCommitment> unified = new ArrayList<>(detected);
        if (bills != null) {
            bills.findPendingBills().stream().map(bill -> asBillCommitment(bill, asOf)).forEach(unified::add);
        }
        if (loans != null) {
            loans.findAllActive().stream().map(loan -> asLoanCommitment(loan, asOf)).forEach(unified::add);
        }
        if (cardEmis != null) {
            cardEmis.findAllActiveEmiPlans().stream().map(plan -> asCardEmiCommitment(plan, asOf)).forEach(unified::add);
        }
        return List.copyOf(unified);
    }

    @Override
    public RecurringCommitmentSummary summarizeFixedCosts(LocalDate asOf, String currency) {
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(currency, "currency cannot be null");
        List<RecurringCommitment> confirmed = list(asOf).stream()
            .filter(commitment -> commitment.status() == RecurringCommitmentStatus.CONFIRMED)
            .filter(commitment -> commitment.expectedAmountRange().minimum().currency().equalsIgnoreCase(currency))
            .toList();
        Money fixedCosts = Money.zero(currency);
        Money variableCosts = Money.zero(currency);
        int variableCount = 0;
        for (RecurringCommitment commitment : confirmed) {
            Money normalized = monthlyAmount(commitment.expectedAmountRange().nominalAmount(), commitment.cadence());
            if (commitment.expectedAmountRange().isVariable()) {
                variableCosts = variableCosts.add(normalized);
                variableCount++;
            } else {
                fixedCosts = fixedCosts.add(normalized);
            }
        }
        Money fixedIncome = Money.zero(currency);
        if (incomeSources != null) {
            for (IncomeSource source : incomeSources.findAll()) {
                if (source.isConfirmed() && source.type() != IncomeSourceType.VARIABLE
                    && source.cadence() != IncomeCadence.ONCE
                    && source.amount().currency().equalsIgnoreCase(currency)) {
                    fixedIncome = fixedIncome.add(
                        monthlyAmount(source.amount(), RecurringCommitmentCadence.valueOf(source.cadence().name()))
                    );
                }
            }
        }
        List<String> warnings = new ArrayList<>();
        if (variableCount > 0) {
            warnings.add("Variable commitments are reported separately and excluded from the fixed-cost ratio.");
        }
        BigDecimal ratio = null;
        if (fixedIncome.isZero()) {
            warnings.add("Fixed-cost ratio is unavailable because no confirmed fixed recurring income is recorded.");
        } else {
            ratio = fixedCosts.amount().divide(fixedIncome.amount(), 4, RoundingMode.HALF_UP);
        }
        return new RecurringCommitmentSummary(
            asOf, "fixed-cost-ratio/v1", IntelligenceClassification.DERIVED_INSIGHT,
            fixedCosts, variableCosts, fixedIncome, ratio, confirmed.size(), variableCount, warnings
        );
    }

    private RecurringCommitment saveOrReuse(RecurringCommitment candidate) {
        return commitments.findByCandidateKey(candidate.candidateKey())
            .map(existing -> {
                if (existing.status() != RecurringCommitmentStatus.CANDIDATE) {
                    return existing;
                }
                commitments.save(candidate);
                return candidate;
            })
            .orElseGet(() -> {
                commitments.save(candidate);
                return candidate;
            });
    }

    private RecurringCommitment candidate(CandidateKey key, List<Transaction> debits, LocalDate asOf) {
        if (debits.size() < 2) {
            return null;
        }
        List<Transaction> ordered = debits.stream()
            .sorted(Comparator.comparing(Transaction::timestamp))
            .toList();
        RecurringCommitmentCadence cadence = inferCadence(ordered);
        if (cadence == null) {
            return null;
        }
        BigDecimal minimum = ordered.stream().map(transaction -> transaction.amount().amount())
            .min(Comparator.naturalOrder()).orElseThrow();
        BigDecimal maximum = ordered.stream().map(transaction -> transaction.amount().amount())
            .max(Comparator.naturalOrder()).orElseThrow();
        String candidateKey = key.normalizedMerchant() + "|" + key.accountId() + "|" + key.currency() + "|" + cadence;
        LocalDate nextPaymentDate = cadence.nextAfter(ordered.getLast().timestamp().toLocalDate());
        ExpectedAmountRange range = new ExpectedAmountRange(
            com.automaticexpense.tracker.domain.Money.of(minimum, key.currency()),
            com.automaticexpense.tracker.domain.Money.of(maximum, key.currency())
        );
        RecurringCommitment result = new RecurringCommitment(
            UUID.nameUUIDFromBytes(("recurring:" + candidateKey).getBytes(StandardCharsets.UTF_8)).toString(),
            ordered.getFirst().merchantName(), classify(ordered.getFirst().merchantName()), cadence, range,
            nextPaymentDate, confidence(ordered, range), ordered.stream().map(Transaction::id).collect(Collectors.toSet()),
            RecurringCommitmentStatus.CANDIDATE,
            range.isVariable() ? RecurringCommitmentState.VARIABLE_AMOUNT : RecurringCommitmentState.ON_TRACK,
            RecurringCommitmentOrigin.DETECTED, null, candidateKey
        );
        return result.asOf(asOf);
    }

    private RecurringCommitmentCadence inferCadence(List<Transaction> ordered) {
        double averageDays = 0;
        for (int index = 1; index < ordered.size(); index++) {
            averageDays += ChronoUnit.DAYS.between(
                ordered.get(index - 1).timestamp().toLocalDate(), ordered.get(index).timestamp().toLocalDate()
            );
        }
        averageDays /= ordered.size() - 1;
        if (isNear(averageDays, 7, 2)) return RecurringCommitmentCadence.WEEKLY;
        if (isNear(averageDays, 14, 3)) return RecurringCommitmentCadence.BIWEEKLY;
        if (isNear(averageDays, 30, 7)) return RecurringCommitmentCadence.MONTHLY;
        if (isNear(averageDays, 91, 14)) return RecurringCommitmentCadence.QUARTERLY;
        if (isNear(averageDays, 365, 35)) return RecurringCommitmentCadence.YEARLY;
        return null;
    }

    private boolean isEligibleDebit(Transaction transaction) {
        return transaction.type() == TransactionType.DEBIT
            && (transaction.reconciliationStatus() == ReconciliationStatus.CONFIRMED
                || transaction.reconciliationStatus() == ReconciliationStatus.AUTO_MERGED)
            && transaction.transferCounterpartMask() == null
            && !EXCLUDED_DEBIT_TEXT.test(transaction.merchantName())
            && !EXCLUDED_DEBIT_TEXT.test(transaction.rawSnippet());
    }

    private RecurringCommitmentClassification classify(String name) {
        String normalized = normalize(name);
        if (normalized.contains("rent")) return RecurringCommitmentClassification.RENT;
        if (normalized.contains("insurance") || normalized.contains("policy")) return RecurringCommitmentClassification.INSURANCE;
        if (normalized.contains("electric") || normalized.contains("water") || normalized.contains("gas")
            || normalized.contains("utility")) return RecurringCommitmentClassification.UTILITY;
        if (normalized.contains("emi") || normalized.contains("installment")) return RecurringCommitmentClassification.EMI;
        if (normalized.contains("gym") || normalized.contains("membership")) return RecurringCommitmentClassification.MEMBERSHIP;
        if (normalized.contains("netflix") || normalized.contains("spotify") || normalized.contains("prime")
            || normalized.contains("stream")) return RecurringCommitmentClassification.SUBSCRIPTION;
        return RecurringCommitmentClassification.OTHER;
    }

    private double confidence(List<Transaction> transactions, ExpectedAmountRange range) {
        return Math.min(0.95, 0.65 + (transactions.size() >= 3 ? 0.20 : 0.10)
            + (range.isVariable() ? 0.0 : 0.10));
    }

    private RecurringCommitment byId(String commitmentId) {
        return commitments.findById(commitmentId)
            .orElseThrow(() -> new IllegalArgumentException("Recurring commitment not found: " + commitmentId));
    }

    private RecurringCommitment asBillCommitment(BillStatement bill, LocalDate asOf) {
        Money lower = bill.minimumDue().compareTo(bill.remainingDue()) <= 0 ? bill.minimumDue() : bill.remainingDue();
        ExpectedAmountRange range = new ExpectedAmountRange(lower, bill.remainingDue());
        return RecurringCommitment.authoritative(
            "bill:" + bill.id(), bill.cardName() + " statement", RecurringCommitmentClassification.OTHER,
            RecurringCommitmentCadence.MONTHLY, range, bill.dueDate(),
            RecurringCommitmentOrigin.AUTHORITATIVE_BILL, bill.id()
        ).asOf(asOf);
    }

    private RecurringCommitment asLoanCommitment(LoanAccount loan, LocalDate asOf) {
        return RecurringCommitment.authoritative(
            "loan:" + loan.id(), loan.loanName(), RecurringCommitmentClassification.EMI,
            RecurringCommitmentCadence.MONTHLY, new ExpectedAmountRange(loan.emiAmount(), loan.emiAmount()),
            loan.nextDueDate(), RecurringCommitmentOrigin.AUTHORITATIVE_LOAN, loan.id()
        ).asOf(asOf);
    }

    private RecurringCommitment asCardEmiCommitment(CardEmiPlan plan, LocalDate asOf) {
        return RecurringCommitment.authoritative(
            "card-emi:" + plan.id(), plan.merchantName() + " card EMI", RecurringCommitmentClassification.EMI,
            RecurringCommitmentCadence.MONTHLY,
            new ExpectedAmountRange(plan.monthlyInstallment(), plan.monthlyInstallment()), plan.nextDueDate(),
            RecurringCommitmentOrigin.AUTHORITATIVE_CARD_EMI, plan.id()
        ).asOf(asOf);
    }

    private Money monthlyAmount(Money amount, RecurringCommitmentCadence cadence) {
        BigDecimal factor = switch (cadence) {
            case WEEKLY -> BigDecimal.valueOf(52).divide(BigDecimal.valueOf(12), 8, RoundingMode.HALF_UP);
            case BIWEEKLY -> BigDecimal.valueOf(26).divide(BigDecimal.valueOf(12), 8, RoundingMode.HALF_UP);
            case MONTHLY -> BigDecimal.ONE;
            case QUARTERLY -> BigDecimal.ONE.divide(BigDecimal.valueOf(3), 8, RoundingMode.HALF_UP);
            case YEARLY -> BigDecimal.ONE.divide(BigDecimal.valueOf(12), 8, RoundingMode.HALF_UP);
        };
        return Money.of(amount.amount().multiply(factor), amount.currency());
    }

    private boolean isReconciledToAuthority(Transaction transaction) {
        String merchant = normalize(transaction.merchantName());
        if (loans != null && loans.findAllActive().stream().anyMatch(loan ->
            merchant.equals(normalize(loan.loanName())) || merchant.equals(normalize(loan.lenderName()))
        )) {
            return true;
        }
        return cardEmis != null && cardEmis.findAllActiveEmiPlans().stream()
            .anyMatch(plan -> merchant.equals(normalize(plan.merchantName())));
    }

    private boolean isNear(double actual, double expected, double tolerance) {
        return Math.abs(actual - expected) <= tolerance;
    }

    private String normalize(String value) {
        return value == null ? "unknown" : value.trim().replaceAll("\\s+", " ").toLowerCase();
    }

    private record CandidateKey(String normalizedMerchant, String accountId, String currency) {}
}
