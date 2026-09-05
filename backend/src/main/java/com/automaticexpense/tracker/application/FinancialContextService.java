package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.application.port.in.CreateFinancialContextItemRequest;
import com.automaticexpense.tracker.application.port.in.EligibleFinancialContextFields;
import com.automaticexpense.tracker.application.port.in.FinancialContextItemView;
import com.automaticexpense.tracker.application.port.in.FinancialContextListView;
import com.automaticexpense.tracker.application.port.in.ManageFinancialContextUseCase;
import com.automaticexpense.tracker.application.port.in.UpdateFinancialContextItemRequest;
import com.automaticexpense.tracker.application.port.out.FinancialContextRepository;
import com.automaticexpense.tracker.domain.FinancialContextCapability;
import com.automaticexpense.tracker.domain.FinancialContextItem;
import com.automaticexpense.tracker.domain.FinancialContextItemStatus;

import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.util.function.Supplier;

public final class FinancialContextService implements ManageFinancialContextUseCase {
    private final FinancialContextRepository repository;
    private final Supplier<Instant> clock;

    public FinancialContextService(FinancialContextRepository repository) {
        this(repository, Instant::now);
    }

    public FinancialContextService(FinancialContextRepository repository, Supplier<Instant> clock) {
        this.repository = Objects.requireNonNull(repository, "repository cannot be null");
        this.clock = Objects.requireNonNull(clock, "clock cannot be null");
    }

    @Override
    public FinancialContextItem create(CreateFinancialContextItemRequest request) {
        Objects.requireNonNull(request, "request cannot be null");
        FinancialContextItem item = FinancialContextItem.create(
            UUID.randomUUID().toString(), request.type(), request.label(), request.values(),
            request.capabilities(), request.provenance(), request.effectiveFrom(), request.effectiveUntil(), clock.get()
        );
        repository.save(item);
        return item;
    }

    @Override
    public FinancialContextItem update(String id, UpdateFinancialContextItemRequest request) {
        Objects.requireNonNull(request, "request cannot be null");
        FinancialContextItem existing = find(id);
        FinancialContextItem updated = existing.update(
            request.label(), request.values(), request.capabilities(),
            request.effectiveFrom(), request.effectiveUntil(), clock.get()
        );
        repository.save(updated);
        return updated;
    }

    @Override
    public FinancialContextItem deactivate(String id) {
        FinancialContextItem deactivated = find(id).deactivate(clock.get());
        repository.save(deactivated);
        return deactivated;
    }

    @Override
    public void delete(String id) {
        find(id);
        repository.delete(id);
    }

    @Override
    public FinancialContextListView list(Instant asOf) {
        Instant checkedAsOf = Objects.requireNonNull(asOf, "asOf cannot be null");
        List<FinancialContextItem> items = repository.findAll().stream()
            .sorted(Comparator.comparing(FinancialContextItem::createdAt).reversed())
            .toList();
        return new FinancialContextListView(checkedAsOf, items.stream()
            .map(item -> viewOf(item, items, checkedAsOf))
            .toList());
    }

    @Override
    public List<EligibleFinancialContextFields> selectEligibleFields(
        FinancialContextCapability capability, Instant asOf
    ) {
        FinancialContextListView list = list(asOf);
        return list.items().stream()
            .filter(view -> view.status() == FinancialContextItemStatus.ACTIVE)
            .filter(view -> view.item().capabilities().contains(capability))
            .map(view -> new EligibleFinancialContextFields(
                view.item().id(), view.item().type(), view.item().minimizedFieldsFor(capability)
            ))
            .toList();
    }

    private FinancialContextItemView viewOf(
        FinancialContextItem item, List<FinancialContextItem> allItems, Instant asOf
    ) {
        List<String> conflictIds = item.isEffectiveAt(asOf)
            ? allItems.stream()
                .filter(other -> !other.id().equals(item.id()))
                .filter(other -> other.isEffectiveAt(asOf))
                .filter(item::conflictsWith)
                .map(FinancialContextItem::id)
                .toList()
            : List.of();
        FinancialContextItemStatus status = conflictIds.isEmpty()
            ? item.statusAt(asOf)
            : FinancialContextItemStatus.CONFLICTING;
        return new FinancialContextItemView(item, status, conflictIds);
    }

    private FinancialContextItem find(String id) {
        return repository.findById(id)
            .orElseThrow(() -> new IllegalArgumentException("Financial context item was not found"));
    }
}
