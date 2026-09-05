package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.ReconcileBillUseCase;
import com.automaticexpense.tracker.application.port.out.BillRepository;
import com.automaticexpense.tracker.domain.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;

class ReconcileBillUseCaseTest {

    private InMemoryBillRepository billRepository;
    private ReconcileBillUseCase billUseCase;

    @BeforeEach
    void setUp() {
        billRepository = new InMemoryBillRepository();
        billUseCase = new BillReconciliationService(billRepository);
    }

    @Test
    void shouldRegisterCreditCardBill() {
        BillStatement bill = billUseCase.registerBill(
            new AccountId("acc-card-hdfc"),
            "HDFC Millennia Credit Card",
            Money.of("28500.00", "INR"),
            Money.of("1500.00", "INR"),
            LocalDate.of(2026, 8, 20),
            LocalDate.of(2026, 9, 10)
        );

        assertThat(bill.id()).isNotBlank();
        assertThat(bill.cardName()).isEqualTo("HDFC Millennia Credit Card");
        assertThat(bill.status()).isEqualTo(BillStatus.PENDING);
        assertThat(bill.totalAmount()).isEqualTo(Money.of("28500.00", "INR"));

        Optional<BillStatement> saved = billRepository.findBillById(bill.id());
        assertThat(saved).isPresent();
    }

    @Test
    void shouldRecordManualBillPayment() {
        BillStatement bill = billUseCase.registerBill(
            new AccountId("acc-card-sbi"),
            "SBI SimplyCLICK",
            Money.of("12000.00", "INR"),
            Money.of("1000.00", "INR"),
            LocalDate.of(2026, 8, 15),
            LocalDate.of(2026, 9, 5)
        );

        BillStatement updated = billUseCase.recordBillPayment(bill.id(), Money.of("12000.00", "INR"));

        assertThat(updated.status()).isEqualTo(BillStatus.PAID);
        assertThat(updated.isPaid()).isTrue();
        assertThat(updated.remainingDue()).isEqualTo(Money.zero("INR"));
    }

    @Test
    void shouldAutoReconcileBillPaymentFromDebitTransaction() {
        BillStatement bill = billUseCase.registerBill(
            new AccountId("acc-card-icici"),
            "ICICI Amazon Pay Card",
            Money.of("14250.00", "INR"),
            Money.of("1000.00", "INR"),
            LocalDate.of(2026, 8, 18),
            LocalDate.of(2026, 9, 8)
        );

        // Bank outgoing debit payment towards credit card bill
        Transaction paymentTx = new Transaction(
            new TransactionId("tx-bill-pay-1"),
            Money.of("14250.00", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 9, 2, 14, 0),
            "Payment to ICICI Credit Card",
            new AccountId("acc-salary"),
            "BILL_PAYMENT",
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            Money.of("14250.00", "INR")
        );

        Optional<BillStatement> reconciled = billUseCase.autoMatchBillPaymentDebit(paymentTx);

        assertThat(reconciled).isPresent();
        assertThat(reconciled.get().id()).isEqualTo(bill.id());
        assertThat(reconciled.get().status()).isEqualTo(BillStatus.PAID);
        assertThat(reconciled.get().isPaid()).isTrue();
    }

    @Test
    void shouldOnlyApplyAnAutomaticallyMatchedDebitOnce() {
        BillStatement bill = billUseCase.registerBill(
            new AccountId("acc-card-hdfc"),
            "HDFC Credit Card",
            Money.of("1000.00", "INR"),
            Money.of("100.00", "INR"),
            LocalDate.of(2026, 8, 18),
            LocalDate.of(2026, 9, 8)
        );
        Transaction paymentTx = new Transaction(
            new TransactionId("tx-bill-pay-once"),
            Money.of("1000.00", "INR"),
            TransactionType.DEBIT,
            LocalDateTime.of(2026, 9, 2, 14, 0),
            "Payment to HDFC Credit Card",
            new AccountId("acc-salary"),
            "BILL_PAYMENT",
            IngestionSource.SMS,
            ReconciliationStatus.CONFIRMED,
            Money.of("1000.00", "INR")
        );

        billUseCase.autoMatchBillPaymentDebit(paymentTx);
        billUseCase.autoMatchBillPaymentDebit(paymentTx);

        BillStatement persisted = billRepository.findBillById(bill.id()).orElseThrow();
        assertThat(persisted.paidAmount()).isEqualTo(Money.of("1000.00", "INR"));
        assertThat(persisted.status()).isEqualTo(BillStatus.PAID);
    }

    private static class InMemoryBillRepository implements BillRepository {
        private final Map<String, BillStatement> store = new HashMap<>();

        @Override
        public void save(BillStatement billStatement) {
            store.put(billStatement.id(), billStatement);
        }

        @Override
        public Optional<BillStatement> findBillById(String billId) {
            return Optional.ofNullable(store.get(billId));
        }

        @Override
        public List<BillStatement> findPendingBills() {
            return store.values().stream().filter(b -> !b.isPaid()).toList();
        }

        @Override
        public List<BillStatement> findAllBills() {
            return new ArrayList<>(store.values());
        }
    }
}
