package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.domain.*;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

public class DynamoDbItem {

    public static Map<String, String> fromAccount(String userId, FinancialAccount account) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "ACC#" + account.id().value());
        item.put("entityType", "ACCOUNT");
        item.put("accountId", account.id().value());
        item.put("name", account.name());
        item.put("type", account.type().name());
        item.put("lastFourDigits", account.lastFourDigits());
        item.put("currency", account.currency());
        item.put("balanceAmount", account.currentBalance().amount().toPlainString());
        return item;
    }

    public static FinancialAccount toAccount(Map<String, String> item) {
        return new FinancialAccount(
            new AccountId(item.get("accountId")),
            item.get("name"),
            AccountType.valueOf(item.get("type")),
            item.get("lastFourDigits"),
            item.get("currency"),
            new Money(new BigDecimal(item.get("balanceAmount")), item.get("currency"))
        );
    }

    public static Map<String, String> fromTransaction(String userId, Transaction transaction) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "TXN#" + transaction.timestamp() + "#" + transaction.id().value());
        item.put("entityType", "TRANSACTION");
        item.put("txnId", transaction.id().value());
        item.put("amount", transaction.amount().amount().toPlainString());
        item.put("currency", transaction.amount().currency());
        item.put("type", transaction.type().name());
        item.put("timestamp", transaction.timestamp().toString());
        item.put("merchantName", transaction.merchantName());
        item.put("accountId", transaction.accountId().value());
        if (transaction.categoryId() != null) {
            item.put("categoryId", transaction.categoryId());
        }
        putIfPresent(item, "subCategory", transaction.subCategory());
        item.put("ingestionSource", transaction.ingestionSource().name());
        item.put("ingestionSources", transaction.ingestionSources().stream()
            .map(Enum::name)
            .sorted()
            .collect(Collectors.joining(",")));
        if (transaction.potentialDuplicateOfTransactionId() != null) {
            item.put("potentialDuplicateOfTransactionId",
                transaction.potentialDuplicateOfTransactionId().value());
        }
        item.put("reconciliationStatus", transaction.reconciliationStatus().name());
        item.put("netPersonalExpense", transaction.netPersonalExpense().amount().toPlainString());
        putIfPresent(item, "accountMask", transaction.accountMask());
        putIfPresent(item, "referenceNumber", transaction.referenceNumber());
        putIfPresent(item, "rawSnippet", transaction.rawSnippet());
        putIfPresent(item, "transferCounterpartMask", transaction.transferCounterpartMask());
        return item;
    }

    public static Transaction toTransaction(Map<String, String> item) {
        Transaction transaction = new Transaction(
            new TransactionId(item.get("txnId")),
            new Money(new BigDecimal(item.get("amount")), item.get("currency")),
            TransactionType.valueOf(item.get("type")),
            LocalDateTime.parse(item.get("timestamp")),
            item.get("merchantName"),
            new AccountId(item.get("accountId")),
            item.get("categoryId"),
            item.get("subCategory"),
            IngestionSource.valueOf(item.get("ingestionSource")),
            ReconciliationStatus.valueOf(item.get("reconciliationStatus")),
            new Money(
                new BigDecimal(item.getOrDefault("netPersonalExpense", item.get("amount"))),
                item.get("currency")
            ),
            item.get("accountMask"),
            item.get("referenceNumber"),
            item.get("rawSnippet"),
            item.get("transferCounterpartMask")
        );
        if (item.containsKey("potentialDuplicateOfTransactionId")) {
            transaction = transaction.withPotentialDuplicateOf(
                new TransactionId(item.get("potentialDuplicateOfTransactionId"))
            );
        }
        if (item.containsKey("ingestionSources")) {
            java.util.Set<IngestionSource> sources = java.util.Arrays.stream(
                    item.get("ingestionSources").split(",")
                )
                .filter(source -> !source.isBlank())
                .map(IngestionSource::valueOf)
                .collect(java.util.stream.Collectors.toSet());
            if (!sources.contains(IngestionSource.valueOf(item.get("ingestionSource")))) {
                throw new IllegalStateException("Transaction evidence must include its primary source");
            }
            transaction = transaction.withIngestionSources(sources);
        }
        return transaction;
    }

    public static Map<String, String> fromVendorRule(String userId, VendorCategoryRule rule) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "RULE#" + rule.payeeKey());
        item.put("entityType", "VENDOR_RULE");
        item.put("payeeKey", rule.payeeKey());
        item.put("rawPayeePattern", rule.rawPayeePattern());
        item.put("categoryId", rule.categoryId());
        putIfPresent(item, "subCategory", rule.subCategory());
        putIfPresent(item, "payeeNickname", rule.payeeNickname());
        item.put("userDefined", Boolean.toString(rule.isUserDefined()));
        return item;
    }

    public static VendorCategoryRule toVendorRule(Map<String, String> item) {
        return new VendorCategoryRule(
            item.get("payeeKey"),
            item.get("rawPayeePattern"),
            item.get("categoryId"),
            item.get("subCategory"),
            item.get("payeeNickname"),
            Boolean.parseBoolean(item.get("userDefined"))
        );
    }

    private static void putIfPresent(Map<String, String> item, String field, String value) {
        if (value != null) {
            item.put(field, value);
        }
    }

    public static Map<String, String> fromPeerDebt(String userId, PeerDebtEntry debt) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "DEBT#" + debt.contactName() + "#" + debt.id());
        item.put("entityType", "PEER_DEBT");
        item.put("debtId", debt.id());
        item.put("contactName", debt.contactName());
        item.put("amount", debt.amount().amount().toPlainString());
        item.put("settledAmount", debt.settledAmount().amount().toPlainString());
        item.put("currency", debt.amount().currency());
        item.put("description", debt.description() != null ? debt.description() : "");
        item.put("isLent", String.valueOf(debt.isLent()));
        item.put("isSettled", String.valueOf(debt.isSettled()));
        if (debt.transactionId() != null) {
            item.put("transactionId", debt.transactionId());
        }
        item.put("createdAt", debt.createdAt().toString());
        if (debt.dueDate() != null) {
            item.put("dueDate", debt.dueDate().toString());
        }
        return item;
    }

    public static PeerDebtEntry toPeerDebt(Map<String, String> item) {
        String currency = item.get("currency");
        Money amount = new Money(new BigDecimal(item.get("amount")), currency);
        Money settledAmount = item.containsKey("settledAmount")
            ? new Money(new BigDecimal(item.get("settledAmount")), currency)
            : Money.zero(currency);

        return new PeerDebtEntry(
            item.get("debtId"),
            item.get("contactName"),
            amount,
            settledAmount,
            item.get("description"),
            Boolean.parseBoolean(item.get("isLent")),
            Boolean.parseBoolean(item.get("isSettled")),
            item.get("transactionId"),
            item.containsKey("createdAt") ? LocalDateTime.parse(item.get("createdAt")) : LocalDateTime.now(),
            item.containsKey("dueDate") && !item.get("dueDate").isBlank() ? java.time.LocalDate.parse(item.get("dueDate")) : null
        );
    }

    public static Map<String, String> fromLoanAccount(String userId, LoanAccount loan) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "LOAN#" + loan.id());
        item.put("entityType", "LOAN");
        item.put("loanId", loan.id());
        item.put("loanName", loan.loanName());
        item.put("lenderName", loan.lenderName());
        item.put("principalAmount", loan.principalAmount().amount().toPlainString());
        item.put("remainingPrincipal", loan.remainingPrincipal().amount().toPlainString());
        item.put("currency", loan.principalAmount().currency());
        item.put("emiAmount", loan.emiAmount().amount().toPlainString());
        item.put("interestRatePercent", String.valueOf(loan.interestRatePercent()));
        item.put("totalInstallments", String.valueOf(loan.totalInstallments()));
        item.put("completedInstallments", String.valueOf(loan.completedInstallments()));
        if (loan.nextDueDate() != null) {
            item.put("nextDueDate", loan.nextDueDate().toString());
        }
        item.put("status", loan.status().name());
        return item;
    }

    public static LoanAccount toLoanAccount(Map<String, String> item) {
        String currency = item.get("currency");
        Money principal = new Money(new BigDecimal(item.get("principalAmount")), currency);
        Money remaining = item.containsKey("remainingPrincipal")
            ? new Money(new BigDecimal(item.get("remainingPrincipal")), currency)
            : principal;
        Money emi = new Money(new BigDecimal(item.get("emiAmount")), currency);

        return new LoanAccount(
            item.get("loanId"),
            item.get("loanName"),
            item.get("lenderName"),
            principal,
            remaining,
            emi,
            Double.parseDouble(item.get("interestRatePercent")),
            Integer.parseInt(item.get("totalInstallments")),
            Integer.parseInt(item.get("completedInstallments")),
            item.containsKey("nextDueDate") && !item.get("nextDueDate").isBlank() ? java.time.LocalDate.parse(item.get("nextDueDate")) : null,
            LoanStatus.valueOf(item.get("status"))
        );
    }

    public static Map<String, String> fromCardEmiPlan(String userId, CardEmiPlan plan) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "CARD_EMI#" + plan.cardAccountId() + "#" + plan.id());
        item.put("entityType", "CARD_EMI");
        item.put("planId", plan.id());
        item.put("cardAccountId", plan.cardAccountId());
        item.put("merchantName", plan.merchantName());
        item.put("totalPrincipal", plan.totalPrincipal().amount().toPlainString());
        item.put("currency", plan.totalPrincipal().currency());
        item.put("monthlyInstallment", plan.monthlyInstallment().amount().toPlainString());
        item.put("interestRatePercent", String.valueOf(plan.interestRatePercent()));
        item.put("totalTenureMonths", String.valueOf(plan.totalTenureMonths()));
        item.put("completedInstallments", String.valueOf(plan.completedInstallments()));
        if (plan.nextDueDate() != null) {
            item.put("nextDueDate", plan.nextDueDate().toString());
        }
        item.put("status", plan.status().name());
        return item;
    }

    public static CardEmiPlan toCardEmiPlan(Map<String, String> item) {
        String currency = item.get("currency");
        Money principal = new Money(new BigDecimal(item.get("totalPrincipal")), currency);
        Money installment = new Money(new BigDecimal(item.get("monthlyInstallment")), currency);

        return new CardEmiPlan(
            item.get("planId"),
            item.get("cardAccountId"),
            item.get("merchantName"),
            principal,
            installment,
            Double.parseDouble(item.get("interestRatePercent")),
            Integer.parseInt(item.get("totalTenureMonths")),
            Integer.parseInt(item.get("completedInstallments")),
            item.containsKey("nextDueDate") && !item.get("nextDueDate").isBlank() ? java.time.LocalDate.parse(item.get("nextDueDate")) : null,
            EmiPlanStatus.valueOf(item.get("status"))
        );
    }

    public static Map<String, String> fromBillStatement(String userId, BillStatement bill) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "BILL#" + bill.id());
        item.put("entityType", "BILL");
        item.put("billId", bill.id());
        item.put("accountId", bill.accountId().value());
        item.put("cardName", bill.cardName());
        item.put("totalAmount", bill.totalAmount().amount().toPlainString());
        item.put("currency", bill.totalAmount().currency());
        item.put("minimumDue", bill.minimumDue().amount().toPlainString());
        item.put("paidAmount", bill.paidAmount().amount().toPlainString());
        item.put("paymentTransactionIds", String.join(",", bill.recordedPaymentTransactionIds()));
        if (bill.statementDate() != null) {
            item.put("statementDate", bill.statementDate().toString());
        }
        item.put("billingCycle", bill.billingCycle().toString());
        item.put("dueDate", bill.dueDate().toString());
        item.put("status", bill.status().name());
        item.put("version", Long.toString(bill.version()));
        return item;
    }

    public static BillStatement toBillStatement(Map<String, String> item) {
        String currency = item.get("currency");
        Money total = new Money(new BigDecimal(item.get("totalAmount")), currency);
        Money min = new Money(new BigDecimal(item.get("minimumDue")), currency);
        Money paid = item.containsKey("paidAmount")
            ? new Money(new BigDecimal(item.get("paidAmount")), currency)
            : Money.zero(currency);

        return new BillStatement(
            item.get("billId"),
            new AccountId(item.get("accountId")),
            item.get("cardName"),
            total,
            min,
            paid,
            item.containsKey("statementDate") && !item.get("statementDate").isBlank() ? java.time.LocalDate.parse(item.get("statementDate")) : null,
            java.time.LocalDate.parse(item.get("dueDate")),
            BillStatus.valueOf(item.get("status")),
            item.containsKey("paymentTransactionIds") && !item.get("paymentTransactionIds").isBlank()
                ? java.util.Set.of(item.get("paymentTransactionIds").split(","))
                : java.util.Set.of(),
            Long.parseLong(item.getOrDefault("version", "0"))
        );
    }

    public static Map<String, String> fromBillReminder(String userId, BillReminder reminder) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "BILL_REMINDER#" + reminder.id());
        item.put("entityType", "BILL_REMINDER");
        item.put("reminderId", reminder.id());
        item.put("billId", reminder.billId());
        item.put("timing", reminder.timing().name());
        item.put("scheduledFor", reminder.scheduledFor().toString());
        item.put("status", reminder.status().name());
        return item;
    }

    public static BillReminder toBillReminder(Map<String, String> item) {
        return new BillReminder(
            item.get("reminderId"),
            item.get("billId"),
            BillReminderTiming.valueOf(item.get("timing")),
            java.time.LocalDate.parse(item.get("scheduledFor")),
            BillReminderStatus.valueOf(item.get("status"))
        );
    }

    public static Map<String, String> fromCategoryBudget(String userId, CategoryBudget budget) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "BUDGET#" + budget.yearMonth() + "#" + budget.categoryId());
        item.put("entityType", "BUDGET");
        item.put("budgetId", budget.id());
        item.put("categoryId", budget.categoryId());
        item.put("categoryName", budget.categoryName());
        item.put("yearMonth", budget.yearMonth());
        item.put("limitAmount", budget.limitAmount().amount().toPlainString());
        item.put("currency", budget.limitAmount().currency());
        item.put("currentSpend", budget.currentSpend().amount().toPlainString());
        return item;
    }

    public static CategoryBudget toCategoryBudget(Map<String, String> item) {
        String currency = item.get("currency");
        Money limit = new Money(new BigDecimal(item.get("limitAmount")), currency);
        Money spend = item.containsKey("currentSpend")
            ? new Money(new BigDecimal(item.get("currentSpend")), currency)
            : Money.zero(currency);

        return new CategoryBudget(
            item.get("budgetId"),
            item.get("categoryId"),
            item.get("categoryName"),
            item.get("yearMonth"),
            limit,
            spend
        );
    }

    public static Map<String, String> fromIncomeSource(String userId, IncomeSource source) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + userId);
        item.put("SK", "INCOME#" + source.id());
        item.put("entityType", "INCOME_SOURCE");
        item.put("incomeSourceId", source.id());
        item.put("name", source.name());
        item.put("incomeSourceType", source.type().name());
        item.put("amount", source.amount().amount().toPlainString());
        item.put("currency", source.amount().currency());
        item.put("cadence", source.cadence().name());
        item.put("effectiveFrom", source.effectiveFrom().toString());
        putIfPresent(item, "effectiveTo", source.effectiveTo() == null ? null : source.effectiveTo().toString());
        item.put("linkedAccountId", source.linkedAccountId().value());
        item.put("confirmationStatus", source.confirmationStatus().name());
        item.put("sourceTransactionIds", source.sourceTransactionIds().stream()
            .map(TransactionId::value)
            .sorted()
            .collect(Collectors.joining(",")));
        putIfPresent(item, "suggestionKey", source.suggestionKey());
        return item;
    }

    public static IncomeSource toIncomeSource(Map<String, String> item) {
        Set<TransactionId> evidence = item.containsKey("sourceTransactionIds")
            && !item.get("sourceTransactionIds").isBlank()
            ? java.util.Arrays.stream(item.get("sourceTransactionIds").split(","))
                .map(TransactionId::new)
                .collect(Collectors.toSet())
            : Set.of();
        return new IncomeSource(
            item.get("incomeSourceId"),
            item.get("name"),
            IncomeSourceType.valueOf(item.get("incomeSourceType")),
            new Money(new BigDecimal(item.get("amount")), item.get("currency")),
            IncomeCadence.valueOf(item.get("cadence")),
            java.time.LocalDate.parse(item.get("effectiveFrom")),
            item.containsKey("effectiveTo") && !item.get("effectiveTo").isBlank()
                ? java.time.LocalDate.parse(item.get("effectiveTo"))
                : null,
            new AccountId(item.get("linkedAccountId")),
            IncomeConfirmationStatus.valueOf(item.get("confirmationStatus")),
            evidence,
            item.get("suggestionKey")
        );
    }

    public static Map<String, String> fromFinancialContextItem(String principal, FinancialContextItem context) {
        Map<String, String> item = new HashMap<>();
        item.put("PK", "USER#" + principal);
        item.put("SK", "CONTEXT#" + context.id());
        item.put("entityType", "FINANCIAL_CONTEXT");
        item.put("contextId", context.id());
        item.put("contextType", context.type().name());
        item.put("label", context.label());
        item.put("values", encodeMap(context.values()));
        item.put("capabilities", context.capabilities().stream().map(Enum::name).sorted().collect(Collectors.joining(",")));
        item.put("provenance", context.provenance().name());
        putIfPresent(item, "effectiveFrom", context.effectiveFrom() == null ? null : context.effectiveFrom().toString());
        putIfPresent(item, "effectiveUntil", context.effectiveUntil() == null ? null : context.effectiveUntil().toString());
        item.put("active", Boolean.toString(context.active()));
        item.put("createdAt", context.createdAt().toString());
        item.put("updatedAt", context.updatedAt().toString());
        return item;
    }

    public static FinancialContextItem toFinancialContextItem(Map<String, String> item) {
        return new FinancialContextItem(
            item.get("contextId"),
            FinancialContextType.valueOf(item.get("contextType")),
            item.get("label"),
            decodeMap(item.get("values")),
            java.util.Arrays.stream(item.get("capabilities").split(","))
                .filter(value -> !value.isBlank())
                .map(FinancialContextCapability::valueOf)
                .collect(java.util.stream.Collectors.toSet()),
            ContextProvenance.valueOf(item.get("provenance")),
            item.containsKey("effectiveFrom") ? java.time.LocalDate.parse(item.get("effectiveFrom")) : null,
            item.containsKey("effectiveUntil") ? java.time.LocalDate.parse(item.get("effectiveUntil")) : null,
            Boolean.parseBoolean(item.getOrDefault("active", "true")),
            Instant.parse(item.get("createdAt")),
            Instant.parse(item.get("updatedAt"))
        );
    }

    private static String encodeMap(Map<String, String> values) {
        return values.entrySet().stream()
            .sorted(Map.Entry.comparingByKey())
            .map(entry -> java.net.URLEncoder.encode(entry.getKey(), java.nio.charset.StandardCharsets.UTF_8)
                + "=" + java.net.URLEncoder.encode(entry.getValue(), java.nio.charset.StandardCharsets.UTF_8))
            .collect(Collectors.joining("&"));
    }

    private static Map<String, String> decodeMap(String encoded) {
        Map<String, String> values = new HashMap<>();
        if (encoded == null || encoded.isBlank()) {
            return values;
        }
        for (String pair : encoded.split("&")) {
            String[] parts = pair.split("=", 2);
            if (parts.length != 2) {
                throw new IllegalArgumentException("Invalid persisted financial context values");
            }
            values.put(
                java.net.URLDecoder.decode(parts[0], java.nio.charset.StandardCharsets.UTF_8),
                java.net.URLDecoder.decode(parts[1], java.nio.charset.StandardCharsets.UTF_8)
            );
        }
        return values;
    }
}
