package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.PlanFinanceQueryUseCase;
import com.automaticexpense.tracker.application.port.out.LanguageModelPort;
import com.automaticexpense.tracker.domain.AccountId;
import com.automaticexpense.tracker.domain.DateRange;
import com.automaticexpense.tracker.domain.FinanceQuery;
import com.automaticexpense.tracker.domain.FinanceQueryAlias;
import com.automaticexpense.tracker.domain.FinanceQueryAliasType;
import com.automaticexpense.tracker.domain.FinanceQueryAliases;
import com.automaticexpense.tracker.domain.FinanceQueryCapability;
import com.automaticexpense.tracker.domain.FinanceQueryCapabilityRegistry;
import com.automaticexpense.tracker.domain.FinanceQueryClarification;
import com.automaticexpense.tracker.domain.FinanceQueryFilters;
import com.automaticexpense.tracker.domain.FinanceQueryPlan;
import com.automaticexpense.tracker.domain.FinanceQueryPlanningResult;
import com.automaticexpense.tracker.domain.LanguageModelPlanningPrompt;
import com.automaticexpense.tracker.domain.LanguageModelPlanningResponse;
import com.automaticexpense.tracker.domain.PlannedFinanceQuery;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class FinanceQueryPlannerService implements PlanFinanceQueryUseCase {
    private static final Pattern YEAR_MONTH = Pattern.compile("\\b(20\\d{2}-(0[1-9]|1[0-2]))\\b");
    private static final Pattern EMAIL = Pattern.compile("\\b[\\w.%+-]+@[\\w.-]+\\.[A-Za-z]{2,}\\b");
    private static final Pattern ACCOUNT_NUMBER = Pattern.compile("\\b\\d{4,}\\b");
    private static final Pattern PERSON_REFERENCE = Pattern.compile(
        "(?i)\\b(to|from|with)\\s+(?!account\\b|the\\b|last\\b|this\\b)[\\p{L}][\\p{L}'-]*\\b"
    );
    private static final String CLARIFICATION =
        "Please clarify the spending measure, period, or registered merchant, category, or account.";

    private final LanguageModelPort languageModel;
    private final FinanceQueryCapabilityRegistry capabilities;

    public FinanceQueryPlannerService() {
        this(null, new FinanceQueryCapabilityRegistry());
    }

    public FinanceQueryPlannerService(LanguageModelPort languageModel) {
        this(languageModel, new FinanceQueryCapabilityRegistry());
    }

    public FinanceQueryPlannerService(
        LanguageModelPort languageModel,
        FinanceQueryCapabilityRegistry capabilities
    ) {
        this.languageModel = languageModel;
        this.capabilities = capabilities;
    }

    @Override
    public FinanceQueryPlanningResult plan(FinanceQuery query, FinanceQueryAliases aliases) {
        Optional<FinanceQueryClarification> ambiguity = ambiguity(query, aliases);
        if (ambiguity.isPresent()) {
            return ambiguity.get();
        }
        if (containsUnresolvableSensitiveReference(query.question())) {
            return new FinanceQueryClarification(CLARIFICATION);
        }
        Optional<FinanceQueryPlan> deterministic = deterministicPlan(query, aliases);
        if (deterministic.isPresent()) {
            return new PlannedFinanceQuery(deterministic.get(), false);
        }
        if (languageModel == null) {
            return new FinanceQueryClarification(CLARIFICATION);
        }
        LanguageModelPlanningResponse response;
        try {
            response = languageModel.plan(prompt(query, aliases));
        } catch (RuntimeException exception) {
            return new FinanceQueryClarification(CLARIFICATION);
        }
        return modelPlan(query, aliases, response)
            .<FinanceQueryPlanningResult>map(plan -> new PlannedFinanceQuery(plan, true))
            .orElseGet(() -> new FinanceQueryClarification(CLARIFICATION));
    }

    private Optional<FinanceQueryPlan> deterministicPlan(FinanceQuery query, FinanceQueryAliases aliases) {
        Optional<DateRange> period = periodFromQuestion(query.question(), query);
        if (period.isEmpty()) {
            return Optional.empty();
        }
        String lower = query.question().toLowerCase(Locale.ROOT);
        FinanceQueryCapability capability;
        if (lower.contains("largest") || lower.contains("biggest") || lower.contains("highest purchase")) {
            capability = FinanceQueryCapability.LARGEST_PURCHASES;
        } else if (lower.contains("evidence") || lower.contains("drill down") || lower.contains("transactions")) {
            capability = FinanceQueryCapability.EVIDENCE_DRILL_DOWN;
        } else if (lower.contains("compare") || lower.contains(" versus ") || lower.contains(" vs ")) {
            capability = FinanceQueryCapability.PERIOD_COMPARISON;
        } else if (lower.contains("categories") || lower.contains("category breakdown")) {
            capability = FinanceQueryCapability.CATEGORY_BREAKDOWN;
        } else if (lower.contains("merchants") || lower.contains("merchant breakdown")) {
            capability = FinanceQueryCapability.MERCHANT_BREAKDOWN;
        } else if (lower.contains("spend") || lower.contains("spent") || lower.contains("expense")) {
            capability = FinanceQueryCapability.SPENDING_TOTAL;
        } else {
            return Optional.empty();
        }
        return Optional.of(new FinanceQueryPlan(capability, filters(period.get(), query, aliases)));
    }

    private Optional<FinanceQueryPlan> modelPlan(
        FinanceQuery query,
        FinanceQueryAliases aliases,
        LanguageModelPlanningResponse response
    ) {
        if (response == null || response.status() != LanguageModelPlanningResponse.Status.PLANNED) {
            return Optional.empty();
        }
        try {
            FinanceQueryCapability capability = FinanceQueryCapability.valueOf(response.capability());
            if (!capabilities.contains(capability)) {
                return Optional.empty();
            }
            DateRange period = periodFromToken(response.period(), query).orElseThrow();
            FinanceQueryAlias merchant = resolve(aliases, FinanceQueryAliasType.MERCHANT, response.merchantAlias());
            FinanceQueryAlias category = resolve(aliases, FinanceQueryAliasType.CATEGORY, response.categoryAlias());
            FinanceQueryAlias account = resolve(aliases, FinanceQueryAliasType.ACCOUNT, response.accountAlias());
            return Optional.of(new FinanceQueryPlan(
                capability,
                new FinanceQueryFilters(
                    period,
                    query.currency(),
                    account == null ? Set.of() : Set.of(new AccountId(account.resolvedValue())),
                    category == null ? null : category.resolvedValue(),
                    merchant == null ? null : merchant.resolvedValue()
                )
            ));
        } catch (IllegalArgumentException | NullPointerException exception) {
            return Optional.empty();
        }
    }

    private FinanceQueryFilters filters(DateRange period, FinanceQuery query, FinanceQueryAliases aliases) {
        FinanceQueryAlias merchant = matched(aliases, FinanceQueryAliasType.MERCHANT, query.question());
        FinanceQueryAlias category = matched(aliases, FinanceQueryAliasType.CATEGORY, query.question());
        FinanceQueryAlias account = matched(aliases, FinanceQueryAliasType.ACCOUNT, query.question());
        return new FinanceQueryFilters(
            period,
            query.currency(),
            account == null ? Set.of() : Set.of(new AccountId(account.resolvedValue())),
            category == null ? null : category.resolvedValue(),
            merchant == null ? null : merchant.resolvedValue()
        );
    }

    private Optional<FinanceQueryClarification> ambiguity(FinanceQuery query, FinanceQueryAliases aliases) {
        for (FinanceQueryAliasType type : FinanceQueryAliasType.values()) {
            if (aliases.matchingSpokenAlias(type, query.question()).size() > 1) {
                return Optional.of(new FinanceQueryClarification(
                    "More than one registered " + type.name().toLowerCase(Locale.ROOT)
                        + " matches that reference. Please use a more specific name."
                ));
            }
        }
        if (periodFromQuestion(query.question(), query).isEmpty()) {
            return Optional.of(new FinanceQueryClarification(
                "Please use a calendar month such as this month, last month, or YYYY-MM."
            ));
        }
        return Optional.empty();
    }

    private FinanceQueryAlias matched(FinanceQueryAliases aliases, FinanceQueryAliasType type, String question) {
        return aliases.matchingSpokenAlias(type, question).stream().findFirst().orElse(null);
    }

    private FinanceQueryAlias resolve(
        FinanceQueryAliases aliases,
        FinanceQueryAliasType type,
        String safeAlias
    ) {
        if (safeAlias == null) {
            return null;
        }
        return aliases.bySafeAlias(type, safeAlias).orElseThrow();
    }

    private LanguageModelPlanningPrompt prompt(FinanceQuery query, FinanceQueryAliases aliases) {
        return new LanguageModelPlanningPrompt(
            sanitizeForProvider(query.question(), aliases),
            capabilities.registeredCapabilities(),
            aliases.safeAliases(FinanceQueryAliasType.MERCHANT),
            aliases.safeAliases(FinanceQueryAliasType.CATEGORY),
            aliases.safeAliases(FinanceQueryAliasType.ACCOUNT)
        );
    }

    private String sanitizeForProvider(String question, FinanceQueryAliases aliases) {
        String sanitized = question;
        List<FinanceQueryAlias> ordered = aliases.entries().stream()
            .sorted(Comparator.comparingInt((FinanceQueryAlias entry) -> entry.spokenAliases().stream()
                .mapToInt(String::length).max().orElse(0)).reversed())
            .toList();
        for (FinanceQueryAlias entry : ordered) {
            for (String spoken : entry.spokenAliases()) {
                sanitized = sanitized.replaceAll("(?i)" + Pattern.quote(spoken), entry.safeAlias());
            }
        }
        sanitized = sanitized.replaceAll(
            "(?i)\\b(at|category|account)\\s+(?!(?:merchant|category|account)-\\d+\\b)[^?.,]+",
            "$1 [redacted-reference]"
        );
        return ACCOUNT_NUMBER.matcher(EMAIL.matcher(sanitized).replaceAll("[redacted-email]"))
            .replaceAll("[redacted-number]");
    }

    private boolean containsUnresolvableSensitiveReference(String question) {
        String lower = question.toLowerCase(Locale.ROOT);
        return lower.contains("contact ") || lower.contains("email ") || lower.contains("account number")
            || PERSON_REFERENCE.matcher(question).find();
    }

    private Optional<DateRange> periodFromQuestion(String question, FinanceQuery query) {
        String lower = question.toLowerCase(Locale.ROOT);
        LocalDate asOf = query.asOf().atZone(query.timezone()).toLocalDate();
        if (lower.contains("this month") || lower.contains("current month")) {
            return Optional.of(month(YearMonth.from(asOf)));
        }
        if (lower.contains("last month") || lower.contains("previous month")) {
            return Optional.of(month(YearMonth.from(asOf).minusMonths(1)));
        }
        Matcher matcher = YEAR_MONTH.matcher(question);
        String specifiedMonth = null;
        while (matcher.find()) {
            if (specifiedMonth != null) {
                return Optional.empty();
            }
            specifiedMonth = matcher.group(1);
        }
        if (specifiedMonth != null) {
            return Optional.of(month(YearMonth.parse(specifiedMonth)));
        }
        if (lower.matches(".*\\b(yesterday|week|year|quarter|january|february|march|april|may|june|july|august|september|october|november|december)\\b.*")) {
            return Optional.empty();
        }
        return Optional.of(month(YearMonth.from(asOf)));
    }

    private Optional<DateRange> periodFromToken(String token, FinanceQuery query) {
        if ("CURRENT_MONTH".equals(token)) {
            return Optional.of(month(YearMonth.from(query.asOf().atZone(query.timezone()))));
        }
        if ("PREVIOUS_MONTH".equals(token)) {
            return Optional.of(month(YearMonth.from(query.asOf().atZone(query.timezone())).minusMonths(1)));
        }
        if (token != null && YEAR_MONTH.matcher(token).matches()) {
            return Optional.of(month(YearMonth.parse(token)));
        }
        return Optional.empty();
    }

    private DateRange month(YearMonth month) {
        return new DateRange(month.atDay(1), month.atEndOfMonth());
    }
}
