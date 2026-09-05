package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ManageIncomeSourceUseCase;
import com.automaticexpense.tracker.application.port.out.IncomeSourceRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.IncomeCadence;
import com.automaticexpense.tracker.domain.IncomeConfirmationStatus;
import com.automaticexpense.tracker.domain.IncomeSource;
import com.automaticexpense.tracker.domain.IncomeSourceType;
import com.automaticexpense.tracker.domain.IncomeSuggestion;
import com.automaticexpense.tracker.domain.IncomeSummary;
import com.automaticexpense.tracker.domain.Money;
import com.automaticexpense.tracker.domain.ReconciliationStatus;
import com.automaticexpense.tracker.domain.Transaction;
import com.automaticexpense.tracker.domain.TransactionId;
import com.automaticexpense.tracker.domain.TransactionType;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.function.Predicate;

/**
 * Classifies a credit as income only after the user has confirmed a source. Suggestions are
 * conservative: unreviewed, non-canonical, transfer-like, refund-like, reversal-like, and
 * loan-like credits are deliberately excluded.
 */
public final class IncomeSourceService implements ManageIncomeSourceUseCase {
    private static final Predicate<String> EXCLUDED_CREDIT_TEXT = text -> {
        String normalized = text == null ? "" : text.toLowerCase();
        return normalized.contains("transfer")
            || normalized.contains("refund")
            || normalized.contains("reversal")
            || normalized.contains("reversed")
            || normalized.contains("chargeback")
            || normalized.contains("loan")
            || normalized.contains("disbursal")
            || normalized.contains("cashback");
    };

    private final IncomeSourceRepository incomeSources;
    private final TransactionRepository transactions;

    public IncomeSourceService(IncomeSourceRepository incomeSources, TransactionRepository transactions) {
        this.incomeSources = Objects.requireNonNull(incomeSources, "incomeSources cannot be null");
        this.transactions = Objects.requireNonNull(transactions, "transactions cannot be null");
    }

    @Override
    public IncomeSource createIncomeSource(
        String name,
        IncomeSourceType type,
        Money amount,
        IncomeCadence cadence,
        LocalDate effectiveFrom,
        LocalDate effectiveTo,
        AccountId linkedAccountId,
        Set<TransactionId> sourceTransactionIds
    ) {
        IncomeSource source = IncomeSource.confirmed(
            UUID.randomUUID().toString(), name, type, amount, cadence, effectiveFrom, effectiveTo,
            linkedAccountId, sourceTransactionIds == null ? Set.of() : sourceTransactionIds
        );
        incomeSources.save(source);
        return source;
    }

    @Override
    public IncomeSource updateEffectiveDates(String incomeSourceId, LocalDate effectiveFrom, LocalDate effectiveTo) {
        IncomeSource updated = sourceById(incomeSourceId).withEffectiveDates(effectiveFrom, effectiveTo);
        incomeSources.save(updated);
        return updated;
    }

    @Override
    public List<IncomeSuggestion> detectIncomeSuggestions() {
        Map<CandidateKey, List<Transaction>> groups = new HashMap<>();
        transactions.findAllTransactions().stream()
            .filter(this::isEligibleCredit)
            .forEach(transaction -> groups.computeIfAbsent(
                new CandidateKey(
                    normalize(transaction.merchantName()),
                    transaction.accountId(),
                    transaction.amount().currency()
                ),
                ignored -> new ArrayList<>()
            ).add(transaction));

        return groups.entrySet().stream()
            .map(entry -> asCandidate(entry.getKey(), entry.getValue()))
            .filter(Objects::nonNull)
            .flatMap(candidate -> persistOrReuse(candidate).stream())
            .toList();
    }

    @Override
    public List<IncomeSuggestion> getUnconfirmedSuggestions() {
        return incomeSources.findAll().stream()
            .filter(source -> source.confirmationStatus() == IncomeConfirmationStatus.PENDING)
            .map(source -> new IncomeSuggestion(source, confidenceForStoredSuggestion(source)))
            .toList();
    }

    @Override
    public IncomeSource confirmSuggestion(String incomeSourceId) {
        IncomeSource current = sourceById(incomeSourceId);
        IncomeSource confirmed = current.confirm();
        if (confirmed.equals(current)) {
            return confirmed;
        }
        return incomeSources.replaceIfPending(confirmed) ? confirmed : sourceById(incomeSourceId);
    }

    @Override
    public IncomeSource rejectSuggestion(String incomeSourceId) {
        IncomeSource current = sourceById(incomeSourceId);
        IncomeSource rejected = current.reject();
        if (rejected.equals(current)) {
            return rejected;
        }
        return incomeSources.replaceIfPending(rejected) ? rejected : sourceById(incomeSourceId);
    }

    @Override
    public List<IncomeSource> getConfirmedIncomeSources() {
        return incomeSources.findAll().stream().filter(IncomeSource::isConfirmed).toList();
    }

    @Override
    public IncomeSummary summarize(LocalDate periodStart, LocalDate periodEnd, LocalDate asOf, String currency) {
        Objects.requireNonNull(periodStart, "periodStart cannot be null");
        Objects.requireNonNull(periodEnd, "periodEnd cannot be null");
        Objects.requireNonNull(asOf, "asOf cannot be null");
        Objects.requireNonNull(currency, "currency cannot be null");

        LocalDate effectivePeriodEnd = periodEnd.isAfter(asOf) ? asOf : periodEnd;
        Money observed = Money.zero(currency);
        Money expected = Money.zero(currency);
        Set<TransactionId> countedEvidence = new HashSet<>();
        List<IncomeSource> confirmed = getConfirmedIncomeSources().stream()
            .filter(source -> source.amount().currency().equalsIgnoreCase(currency))
            .toList();

        for (IncomeSource source : confirmed) {
            expected = expected.add(expectedFor(source, periodStart, effectivePeriodEnd));
            for (TransactionId transactionId : source.sourceTransactionIds()) {
                if (countedEvidence.add(transactionId)) {
                    observed = transactions.findById(transactionId)
                        .filter(this::isEligibleCredit)
                        .filter(transaction -> transaction.amount().currency().equalsIgnoreCase(currency))
                        .filter(transaction -> isInPeriod(transaction.timestamp().toLocalDate(), periodStart, periodEnd))
                        .filter(transaction -> !transaction.timestamp().toLocalDate().isAfter(asOf))
                        .map(Transaction::amount)
                        .map(observed::add)
                        .orElse(observed);
                }
            }
        }

        List<IncomeSource> pending = incomeSources.findAll().stream()
            .filter(source -> source.confirmationStatus() == IncomeConfirmationStatus.PENDING)
            .filter(source -> source.amount().currency().equalsIgnoreCase(currency))
            .filter(source -> overlaps(source, periodStart, effectivePeriodEnd))
            .filter(source -> hasEvidenceAtOrBefore(source, asOf))
            .toList();
        Money uncertain = pending.stream()
            .map(source -> expectedFor(source, periodStart, effectivePeriodEnd))
            .reduce(Money.zero(currency), Money::add);

        return new IncomeSummary(
            periodStart, periodEnd, asOf, observed, expected, uncertain, confirmed.size(), pending.size()
        );
    }

    private List<IncomeSuggestion> persistOrReuse(Candidate candidate) {
        return incomeSources.findBySuggestionKey(candidate.suggestionKey())
            .filter(existing -> existing.confirmationStatus() == IncomeConfirmationStatus.PENDING)
            .map(existing -> {
                IncomeSource refreshed = new IncomeSource(
                    existing.id(), candidate.name(), candidate.type(), candidate.amount(), candidate.cadence(),
                    candidate.effectiveFrom(), null, candidate.accountId(), existing.confirmationStatus(),
                    candidate.evidence(), existing.suggestionKey()
                );
                return incomeSources.replaceIfPending(refreshed)
                    ? List.of(new IncomeSuggestion(refreshed, candidate.confidence()))
                    : List.<IncomeSuggestion>of();
            })
            .orElseGet(() -> {
                if (incomeSources.findBySuggestionKey(candidate.suggestionKey()).isPresent()) {
                    return List.of();
                }
                IncomeSource suggestion = IncomeSource.suggested(
                    UUID.nameUUIDFromBytes(("income:" + candidate.suggestionKey())
                        .getBytes(StandardCharsets.UTF_8)).toString(),
                    candidate.name(), candidate.type(), candidate.amount(), candidate.cadence(),
                    candidate.effectiveFrom(), null, candidate.accountId(), candidate.evidence(),
                    candidate.suggestionKey()
                );
                incomeSources.save(suggestion);
                return List.of(new IncomeSuggestion(suggestion, candidate.confidence()));
            });
    }

    private Candidate asCandidate(CandidateKey key, List<Transaction> credits) {
        if (credits.size() < 2) {
            return null;
        }
        List<Transaction> ordered = credits.stream()
            .sorted(Comparator.comparing(Transaction::timestamp))
            .toList();
        IncomeCadence cadence = inferCadence(ordered);
        if (cadence == null) {
            return null;
        }
        boolean fixedAmount = ordered.stream()
            .map(transaction -> transaction.amount().amount())
            .distinct()
            .count() == 1;
        BigDecimal medianAmount = ordered.stream()
            .map(transaction -> transaction.amount().amount())
            .sorted()
            .skip((ordered.size() - 1L) / 2)
            .findFirst()
            .orElseThrow();
        double confidence = Math.min(1.0,
            0.70 + 0.15 + (fixedAmount ? 0.10 : 0.0) + (ordered.size() >= 3 ? 0.05 : 0.0));
        return new Candidate(
            ordered.getFirst().merchantName(),
            fixedAmount ? IncomeSourceType.FIXED : IncomeSourceType.VARIABLE,
            Money.of(medianAmount, key.currency()),
            cadence,
            ordered.getFirst().timestamp().toLocalDate(),
            key.accountId(),
            ordered.stream().map(Transaction::id).collect(java.util.stream.Collectors.toSet()),
            key.normalizedMerchant() + "|" + key.accountId().value() + "|" + key.currency() + "|" + cadence,
            confidence
        );
    }

    private IncomeCadence inferCadence(List<Transaction> ordered) {
        double averageDays = 0;
        for (int index = 1; index < ordered.size(); index++) {
            averageDays += ChronoUnit.DAYS.between(
                ordered.get(index - 1).timestamp().toLocalDate(),
                ordered.get(index).timestamp().toLocalDate()
            );
        }
        averageDays /= ordered.size() - 1;
        if (isNear(averageDays, 7, 2)) return IncomeCadence.WEEKLY;
        if (isNear(averageDays, 14, 3)) return IncomeCadence.BIWEEKLY;
        if (isNear(averageDays, 30, 7)) return IncomeCadence.MONTHLY;
        if (isNear(averageDays, 91, 14)) return IncomeCadence.QUARTERLY;
        if (isNear(averageDays, 365, 35)) return IncomeCadence.YEARLY;
        return null;
    }

    private boolean isEligibleCredit(Transaction transaction) {
        return transaction.type() == TransactionType.CREDIT
            && (transaction.reconciliationStatus() == ReconciliationStatus.CONFIRMED
                || transaction.reconciliationStatus() == ReconciliationStatus.AUTO_MERGED)
            && transaction.transferCounterpartMask() == null
            && !EXCLUDED_CREDIT_TEXT.test(transaction.merchantName())
            && !EXCLUDED_CREDIT_TEXT.test(transaction.rawSnippet());
    }

    private Money expectedFor(IncomeSource source, LocalDate periodStart, LocalDate periodEnd) {
        int occurrences = 0;
        for (LocalDate date = source.effectiveFrom();
             !date.isAfter(periodEnd) && (source.effectiveTo() == null || !date.isAfter(source.effectiveTo()));
             date = nextOccurrence(date, source.cadence())) {
            if (!date.isBefore(periodStart)) {
                occurrences++;
            }
            if (source.cadence() == IncomeCadence.ONCE) {
                break;
            }
        }
        return Money.of(source.amount().amount().multiply(BigDecimal.valueOf(occurrences)), source.amount().currency());
    }

    private LocalDate nextOccurrence(LocalDate date, IncomeCadence cadence) {
        return switch (cadence) {
            case ONCE -> date;
            case WEEKLY -> date.plusWeeks(1);
            case BIWEEKLY -> date.plusWeeks(2);
            case MONTHLY -> date.plusMonths(1);
            case QUARTERLY -> date.plusMonths(3);
            case YEARLY -> date.plusYears(1);
        };
    }

    private IncomeSource sourceById(String incomeSourceId) {
        return incomeSources.findById(incomeSourceId)
            .orElseThrow(() -> new IllegalArgumentException("Income source not found: " + incomeSourceId));
    }

    private double confidenceForStoredSuggestion(IncomeSource source) {
        return Math.min(0.95, 0.60 + (source.sourceTransactionIds().size() * 0.10));
    }

    private boolean overlaps(IncomeSource source, LocalDate periodStart, LocalDate periodEnd) {
        return !source.effectiveFrom().isAfter(periodEnd)
            && (source.effectiveTo() == null || !source.effectiveTo().isBefore(periodStart));
    }

    private boolean hasEvidenceAtOrBefore(IncomeSource source, LocalDate asOf) {
        return source.sourceTransactionIds().stream()
            .map(transactions::findById)
            .flatMap(Optional::stream)
            .anyMatch(transaction -> !transaction.timestamp().toLocalDate().isAfter(asOf));
    }

    private boolean isInPeriod(LocalDate date, LocalDate start, LocalDate end) {
        return !date.isBefore(start) && !date.isAfter(end);
    }

    private boolean isNear(double actual, double expected, double tolerance) {
        return Math.abs(actual - expected) <= tolerance;
    }

    private String normalize(String value) {
        return value == null ? "unknown" : value.trim().replaceAll("\\s+", " ").toLowerCase();
    }

    private record CandidateKey(String normalizedMerchant, AccountId accountId, String currency) {}

    private record Candidate(
        String name,
        IncomeSourceType type,
        Money amount,
        IncomeCadence cadence,
        LocalDate effectiveFrom,
        AccountId accountId,
        Set<TransactionId> evidence,
        String suggestionKey,
        double confidence
    ) {}
}
