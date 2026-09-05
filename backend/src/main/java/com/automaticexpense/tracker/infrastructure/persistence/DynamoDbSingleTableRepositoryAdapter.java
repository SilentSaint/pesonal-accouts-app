package com.automaticexpense.tracker.infrastructure.persistence;

import com.automaticexpense.tracker.application.port.out.AccountRepository;
import com.automaticexpense.tracker.application.port.out.TransactionRepository;
import com.automaticexpense.tracker.application.port.out.CanonicalTransactionRepository;
import com.automaticexpense.tracker.application.port.out.PeerDebtRepository;
import com.automaticexpense.tracker.application.port.out.LoanRepository;
import com.automaticexpense.tracker.application.port.out.CardEmiRepository;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.application.port.out.BillReminderRepository;
import com.automaticexpense.tracker.application.port.out.BudgetRepository;
import com.automaticexpense.tracker.application.port.out.VendorRuleRepository;
import com.automaticexpense.tracker.domain.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

public class DynamoDbSingleTableRepositoryAdapter implements AccountRepository, TransactionRepository, CanonicalTransactionRepository, PeerDebtRepository, LoanRepository, CardEmiRepository, BillRepository, BillReminderRepository, BudgetRepository, VendorRuleRepository {

    private final String userId;
    private final Map<String, Map<String, String>> tableStorage = new ConcurrentHashMap<>();

    public DynamoDbSingleTableRepositoryAdapter(String userId) {
        this.userId = userId;
    }

    @Override
    public void save(FinancialAccount account) {
        Map<String, String> item = DynamoDbItem.fromAccount(userId, account);
        tableStorage.put(item.get("SK"), item);
    }

    @Override
    public Optional<FinancialAccount> findById(AccountId id) {
        String sk = "ACC#" + id.value();
        Map<String, String> item = tableStorage.get(sk);
        return Optional.ofNullable(item).map(DynamoDbItem::toAccount);
    }

    @Override
    public Optional<FinancialAccount> findByLastFourDigits(String lastFourDigits) {
        return tableStorage.values().stream()
            .filter(item -> "ACCOUNT".equals(item.get("entityType")))
            .filter(item -> lastFourDigits.equals(item.get("lastFourDigits")))
            .map(DynamoDbItem::toAccount)
            .findFirst();
    }

    @Override
    public void save(Transaction transaction) {
        Map<String, String> item = DynamoDbItem.fromTransaction(userId, transaction);
        tableStorage.put(item.get("SK"), item);
    }

    @Override
    public Optional<Transaction> findById(TransactionId id) {
        return tableStorage.values().stream()
            .filter(item -> "TRANSACTION".equals(item.get("entityType")))
            .filter(item -> id.value().equals(item.get("txnId")))
            .map(DynamoDbItem::toTransaction)
            .findFirst();
    }

    @Override
    public List<Transaction> findByAccountId(AccountId accountId) {
        List<Transaction> result = new ArrayList<>();
        for (Map<String, String> item : tableStorage.values()) {
            if ("TRANSACTION".equals(item.get("entityType")) && accountId.value().equals(item.get("accountId"))) {
                result.add(DynamoDbItem.toTransaction(item));
            }
        }
        return result;
    }

    @Override
    public List<Transaction> findByReconciliationStatus(ReconciliationStatus status) {
        return tableStorage.values().stream()
            .filter(item -> "TRANSACTION".equals(item.get("entityType")))
            .map(DynamoDbItem::toTransaction)
            .filter(txn -> txn.reconciliationStatus() == status)
            .collect(Collectors.toList());
    }

    @Override
    public List<Transaction> findByAccountIdAndWindow(AccountId accountId, LocalDateTime startTime, LocalDateTime endTime) {
        return tableStorage.values().stream()
            .filter(item -> "TRANSACTION".equals(item.get("entityType")))
            .map(DynamoDbItem::toTransaction)
            .filter(txn -> txn.accountId().equals(accountId))
            .filter(txn -> !txn.timestamp().isBefore(startTime) && !txn.timestamp().isAfter(endTime))
            .collect(Collectors.toList());
    }

    @Override
    public List<Transaction> findAllTransactions() {
        return tableStorage.values().stream()
            .filter(item -> "TRANSACTION".equals(item.get("entityType")))
            .map(DynamoDbItem::toTransaction)
            .collect(Collectors.toList());
    }

    @Override
    public void delete(TransactionId id) {
        tableStorage.values().removeIf(item -> "TRANSACTION".equals(item.get("entityType")) && id.value().equals(item.get("txnId")));
    }

    @Override
    public synchronized boolean mergeCanonically(Transaction canonical, Transaction duplicate) {
        if (findById(duplicate.id()).isEmpty()) {
            return false;
        }
        save(canonical);
        delete(duplicate.id());
        return true;
    }

    @Override
    public synchronized boolean confirmAsSeparate(FinancialAccount account, Transaction transaction) {
        Transaction stored = findById(transaction.id()).orElse(null);
        if (stored == null || stored.potentialDuplicateOfTransactionId() == null) {
            return false;
        }
        save(account);
        save(transaction);
        return true;
    }

    @Override
    public void save(PeerDebtEntry debtEntry) {
        Map<String, String> item = DynamoDbItem.fromPeerDebt(userId, debtEntry);
        tableStorage.put(item.get("SK"), item);
    }

    @Override
    public Optional<PeerDebtEntry> findDebtById(String id) {
        return tableStorage.values().stream()
            .filter(item -> "PEER_DEBT".equals(item.get("entityType")))
            .filter(item -> id.equals(item.get("debtId")))
            .map(DynamoDbItem::toPeerDebt)
            .findFirst();
    }

    @Override
    public List<PeerDebtEntry> findByContactName(String contactName) {
        return tableStorage.values().stream()
            .filter(item -> "PEER_DEBT".equals(item.get("entityType")))
            .filter(item -> contactName.equalsIgnoreCase(item.get("contactName")))
            .map(DynamoDbItem::toPeerDebt)
            .collect(Collectors.toList());
    }

    @Override
    public List<PeerDebtEntry> findAllUnsettled() {
        return tableStorage.values().stream()
            .filter(item -> "PEER_DEBT".equals(item.get("entityType")))
            .map(DynamoDbItem::toPeerDebt)
            .filter(d -> !d.isSettled())
            .collect(Collectors.toList());
    }

    @Override
    public List<PeerDebtEntry> findAllDebts() {
        return tableStorage.values().stream()
            .filter(item -> "PEER_DEBT".equals(item.get("entityType")))
            .map(DynamoDbItem::toPeerDebt)
            .collect(Collectors.toList());
    }

    @Override
    public void save(LoanAccount loanAccount) {
        Map<String, String> item = DynamoDbItem.fromLoanAccount(userId, loanAccount);
        tableStorage.put(item.get("SK"), item);
    }

    @Override
    public Optional<LoanAccount> findLoanById(String loanId) {
        return tableStorage.values().stream()
            .filter(item -> "LOAN".equals(item.get("entityType")))
            .filter(item -> loanId.equals(item.get("loanId")))
            .map(DynamoDbItem::toLoanAccount)
            .findFirst();
    }

    @Override
    public List<LoanAccount> findAllActive() {
        return tableStorage.values().stream()
            .filter(item -> "LOAN".equals(item.get("entityType")))
            .map(DynamoDbItem::toLoanAccount)
            .filter(l -> !l.isClosed())
            .collect(Collectors.toList());
    }

    @Override
    public List<LoanAccount> findAllLoans() {
        return tableStorage.values().stream()
            .filter(item -> "LOAN".equals(item.get("entityType")))
            .map(DynamoDbItem::toLoanAccount)
            .collect(Collectors.toList());
    }

    @Override
    public void save(CardEmiPlan emiPlan) {
        Map<String, String> item = DynamoDbItem.fromCardEmiPlan(userId, emiPlan);
        tableStorage.put(item.get("SK"), item);
    }

    @Override
    public Optional<CardEmiPlan> findEmiPlanById(String planId) {
        return tableStorage.values().stream()
            .filter(item -> "CARD_EMI".equals(item.get("entityType")))
            .filter(item -> planId.equals(item.get("planId")))
            .map(DynamoDbItem::toCardEmiPlan)
            .findFirst();
    }

    @Override
    public List<CardEmiPlan> findActiveByCardId(String cardAccountId) {
        return tableStorage.values().stream()
            .filter(item -> "CARD_EMI".equals(item.get("entityType")))
            .filter(item -> cardAccountId.equals(item.get("cardAccountId")))
            .map(DynamoDbItem::toCardEmiPlan)
            .filter(p -> !p.isCompleted())
            .collect(Collectors.toList());
    }

    @Override
    public List<CardEmiPlan> findAllActiveEmiPlans() {
        return tableStorage.values().stream()
            .filter(item -> "CARD_EMI".equals(item.get("entityType")))
            .map(DynamoDbItem::toCardEmiPlan)
            .filter(p -> !p.isCompleted())
            .collect(Collectors.toList());
    }

    @Override
    public List<CardEmiPlan> findAllEmiPlans() {
        return tableStorage.values().stream()
            .filter(item -> "CARD_EMI".equals(item.get("entityType")))
            .map(DynamoDbItem::toCardEmiPlan)
            .collect(Collectors.toList());
    }

    @Override
    public void save(BillStatement billStatement) {
        Map<String, String> item = DynamoDbItem.fromBillStatement(userId, billStatement);
        tableStorage.put(item.get("SK"), item);
    }

    @Override
    public Optional<BillStatement> findBillById(String billId) {
        return tableStorage.values().stream()
            .filter(item -> "BILL".equals(item.get("entityType")))
            .filter(item -> billId.equals(item.get("billId")))
            .map(DynamoDbItem::toBillStatement)
            .findFirst();
    }

    @Override
    public List<BillStatement> findPendingBills() {
        return tableStorage.values().stream()
            .filter(item -> "BILL".equals(item.get("entityType")))
            .map(DynamoDbItem::toBillStatement)
            .filter(b -> !b.isPaid())
            .collect(Collectors.toList());
    }

    @Override
    public List<BillStatement> findAllBills() {
        return tableStorage.values().stream()
            .filter(item -> "BILL".equals(item.get("entityType")))
            .map(DynamoDbItem::toBillStatement)
            .collect(Collectors.toList());
    }

    @Override
    public synchronized Optional<BillStatement> recordPaymentAtomically(
        String billId,
        String paymentTransactionId,
        Money paymentAmount
    ) {
        BillStatement bill = findBillById(billId).orElse(null);
        if (bill == null) {
            return Optional.empty();
        }
        if (bill.recordPayment(paymentTransactionId, paymentAmount)) {
            save(bill.withIncrementedVersion());
        }
        return Optional.of(bill);
    }

    @Override
    public synchronized boolean scheduleIfAbsent(BillReminder reminder) {
        Map<String, String> item = DynamoDbItem.fromBillReminder(userId, reminder);
        return tableStorage.putIfAbsent(item.get("SK"), item) == null;
    }

    @Override
    public List<BillReminder> findScheduledFor(LocalDate date) {
        return tableStorage.values().stream()
            .filter(item -> "BILL_REMINDER".equals(item.get("entityType")))
            .map(DynamoDbItem::toBillReminder)
            .filter(reminder -> reminder.scheduledFor().equals(date))
            .filter(reminder -> reminder.status() == BillReminderStatus.SCHEDULED)
            .toList();
    }

    @Override
    public synchronized Optional<BillReminder> claim(String reminderId) {
        String sk = "BILL_REMINDER#" + reminderId;
        Map<String, String> item = tableStorage.get(sk);
        if (item == null) {
            return Optional.empty();
        }
        BillReminder reminder = DynamoDbItem.toBillReminder(item);
        if (reminder.status() != BillReminderStatus.SCHEDULED) {
            return Optional.empty();
        }
        BillReminder claimed = reminder.withStatus(BillReminderStatus.CLAIMED);
        tableStorage.put(sk, DynamoDbItem.fromBillReminder(userId, claimed));
        return Optional.of(claimed);
    }

    @Override
    public synchronized void markDelivered(String reminderId) {
        updateReminderStatus(reminderId, BillReminderStatus.DELIVERED);
    }

    @Override
    public synchronized void releaseClaim(String reminderId) {
        updateReminderStatus(reminderId, BillReminderStatus.SCHEDULED);
    }

    @Override
    public synchronized void cancel(String reminderId) {
        updateReminderStatus(reminderId, BillReminderStatus.CANCELLED);
    }

    private void updateReminderStatus(String reminderId, BillReminderStatus status) {
        String sk = "BILL_REMINDER#" + reminderId;
        Map<String, String> item = tableStorage.get(sk);
        if (item != null) {
            tableStorage.put(sk, DynamoDbItem.fromBillReminder(
                userId, DynamoDbItem.toBillReminder(item).withStatus(status)
            ));
        }
    }

    @Override
    public void save(CategoryBudget budget) {
        Map<String, String> item = DynamoDbItem.fromCategoryBudget(userId, budget);
        tableStorage.put(item.get("SK"), item);
    }

    @Override
    public Optional<CategoryBudget> findBudget(String categoryId, String yearMonth) {
        return tableStorage.values().stream()
            .filter(item -> "BUDGET".equals(item.get("entityType")))
            .filter(item -> categoryId.equals(item.get("categoryId")) && yearMonth.equals(item.get("yearMonth")))
            .map(DynamoDbItem::toCategoryBudget)
            .findFirst();
    }

    @Override
    public List<CategoryBudget> findBudgetsForMonth(String yearMonth) {
        return tableStorage.values().stream()
            .filter(item -> "BUDGET".equals(item.get("entityType")))
            .filter(item -> yearMonth.equals(item.get("yearMonth")))
            .map(DynamoDbItem::toCategoryBudget)
            .collect(Collectors.toList());
    }

    @Override
    public List<CategoryBudget> findAllBudgets() {
        return tableStorage.values().stream()
            .filter(item -> "BUDGET".equals(item.get("entityType")))
            .map(DynamoDbItem::toCategoryBudget)
            .collect(Collectors.toList());
    }

    @Override
    public void save(VendorCategoryRule rule) {
        Map<String, String> item = DynamoDbItem.fromVendorRule(userId, rule);
        tableStorage.put(item.get("SK"), item);
    }

    @Override
    public Optional<VendorCategoryRule> findByPayeeKey(String payeeKey) {
        Map<String, String> item = tableStorage.get("RULE#" + VendorCategoryRule.normalizePayeeKey(payeeKey));
        return Optional.ofNullable(item).map(DynamoDbItem::toVendorRule);
    }

    @Override
    public List<VendorCategoryRule> findAll() {
        return tableStorage.values().stream()
            .filter(item -> "VENDOR_RULE".equals(item.get("entityType")))
            .map(DynamoDbItem::toVendorRule)
            .collect(Collectors.toList());
    }
}

