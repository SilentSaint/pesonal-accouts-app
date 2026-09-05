package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.CreateFinancialContextItemRequest;
import com.automaticexpense.tracker.application.port.in.FinancialContextListView;
import com.automaticexpense.tracker.application.port.in.ManageFinancialContextUseCase;
import com.automaticexpense.tracker.application.port.out.FinancialContextRepository;
import com.automaticexpense.tracker.domain.ContextProvenance;
import com.automaticexpense.tracker.domain.FinancialContextCapability;
import com.automaticexpense.tracker.domain.FinancialContextItem;
import com.automaticexpense.tracker.domain.FinancialContextType;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class ManageFinancialContextUseCaseTest {

    @Test
    void surfacesConflictingCashFloorsAndExcludesBothFromEligibleConsumerFields() {
        ManageFinancialContextUseCase context = new FinancialContextService(
            new InMemoryFinancialContextRepository(), () -> Instant.parse("2026-08-29T10:00:00Z")
        );
        context.create(new CreateFinancialContextItemRequest(
            FinancialContextType.PREFERRED_MINIMUM_CASH_BALANCE,
            "Household floor",
            Map.of("amount", "25000.00", "currency", "INR"),
            Set.of(FinancialContextCapability.CASH_FLOW_FORECAST),
            ContextProvenance.USER_DECLARED,
            LocalDate.of(2026, 8, 1),
            null
        ));
        context.create(new CreateFinancialContextItemRequest(
            FinancialContextType.PREFERRED_MINIMUM_CASH_BALANCE,
            "Personal floor",
            Map.of("amount", "10000.00", "currency", "INR"),
            Set.of(FinancialContextCapability.CASH_FLOW_FORECAST),
            ContextProvenance.USER_DECLARED,
            LocalDate.of(2026, 8, 1),
            null
        ));

        FinancialContextListView listed = context.list(Instant.parse("2026-08-29T10:00:00Z"));

        assertThat(listed.items()).allSatisfy(item -> assertThat(item.conflictIds()).hasSize(1));
        assertThat(context.selectEligibleFields(
            FinancialContextCapability.CASH_FLOW_FORECAST,
            Instant.parse("2026-08-29T10:00:00Z")
        )).isEmpty();
    }

    private static final class InMemoryFinancialContextRepository implements FinancialContextRepository {
        private final List<FinancialContextItem> items = new ArrayList<>();

        @Override
        public void save(FinancialContextItem item) {
            items.removeIf(existing -> existing.id().equals(item.id()));
            items.add(item);
        }

        @Override
        public Optional<FinancialContextItem> findById(String id) {
            return items.stream().filter(item -> item.id().equals(id)).findFirst();
        }

        @Override
        public List<FinancialContextItem> findAll() {
            return items.stream().sorted(Comparator.comparing(FinancialContextItem::createdAt)).toList();
        }

        @Override
        public void delete(String id) {
            items.removeIf(item -> item.id().equals(id));
        }
    }
}
