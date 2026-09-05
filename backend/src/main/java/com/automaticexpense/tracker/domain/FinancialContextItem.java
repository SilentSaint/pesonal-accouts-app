package com.automaticexpense.tracker.domain;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * Explicit user-managed analysis context. It intentionally has no inferred provenance.
 */
public record FinancialContextItem(
    String id,
    FinancialContextType type,
    String label,
    Map<String, String> values,
    Set<FinancialContextCapability> capabilities,
    ContextProvenance provenance,
    LocalDate effectiveFrom,
    LocalDate effectiveUntil,
    boolean active,
    Instant createdAt,
    Instant updatedAt
) {
    public FinancialContextItem {
        requireText(id, "id");
        type = Objects.requireNonNull(type, "type cannot be null");
        requireText(label, "label");
        values = Map.copyOf(new LinkedHashMap<>(Objects.requireNonNull(values, "values cannot be null")));
        capabilities = Set.copyOf(Objects.requireNonNull(capabilities, "capabilities cannot be null"));
        provenance = Objects.requireNonNull(provenance, "provenance cannot be null");
        createdAt = Objects.requireNonNull(createdAt, "createdAt cannot be null");
        updatedAt = Objects.requireNonNull(updatedAt, "updatedAt cannot be null");
        if (capabilities.isEmpty() || !type.allowedCapabilities().containsAll(capabilities)) {
            throw new IllegalArgumentException("Capabilities are not allowed for context type " + type);
        }
        if (effectiveUntil != null && effectiveFrom != null && effectiveUntil.isBefore(effectiveFrom)) {
            throw new IllegalArgumentException("effectiveUntil cannot precede effectiveFrom");
        }
        type.validateValues(values);
    }

    public static FinancialContextItem create(
        String id,
        FinancialContextType type,
        String label,
        Map<String, String> values,
        Set<FinancialContextCapability> capabilities,
        ContextProvenance provenance,
        LocalDate effectiveFrom,
        LocalDate effectiveUntil,
        Instant now
    ) {
        return new FinancialContextItem(
            id, type, label, values, capabilities, provenance, effectiveFrom, effectiveUntil, true, now, now
        );
    }

    public FinancialContextItem update(
        String label,
        Map<String, String> values,
        Set<FinancialContextCapability> capabilities,
        LocalDate effectiveFrom,
        LocalDate effectiveUntil,
        Instant now
    ) {
        return new FinancialContextItem(
            id, type, label, values, capabilities, provenance, effectiveFrom, effectiveUntil, active, createdAt, now
        );
    }

    public FinancialContextItem deactivate(Instant now) {
        return new FinancialContextItem(
            id, type, label, values, capabilities, provenance, effectiveFrom, effectiveUntil, false, createdAt, now
        );
    }

    public FinancialContextItemStatus statusAt(Instant asOf) {
        if (!active) {
            return FinancialContextItemStatus.INACTIVE;
        }
        LocalDate date = asOf.atZone(ZoneOffset.UTC).toLocalDate();
        if ((effectiveFrom != null && date.isBefore(effectiveFrom))
            || (effectiveUntil != null && date.isAfter(effectiveUntil))) {
            return FinancialContextItemStatus.EXPIRED;
        }
        return FinancialContextItemStatus.ACTIVE;
    }

    public boolean isEffectiveAt(Instant asOf) {
        return statusAt(asOf) == FinancialContextItemStatus.ACTIVE;
    }

    public boolean conflictsWith(FinancialContextItem other) {
        if (other == null || !type.singleton() || type != other.type) {
            return false;
        }
        return dateRangesOverlap(effectiveFrom, effectiveUntil, other.effectiveFrom, other.effectiveUntil);
    }

    public Map<String, String> minimizedFieldsFor(FinancialContextCapability capability) {
        if (!capabilities.contains(capability)) {
            return Map.of();
        }
        Map<String, String> result = new LinkedHashMap<>();
        type.minimizedFields().forEach(field -> result.put(field, values.get(field)));
        return Map.copyOf(result);
    }

    private static boolean dateRangesOverlap(
        LocalDate leftFrom, LocalDate leftUntil, LocalDate rightFrom, LocalDate rightUntil
    ) {
        return (leftUntil == null || rightFrom == null || !leftUntil.isBefore(rightFrom))
            && (rightUntil == null || leftFrom == null || !rightUntil.isBefore(leftFrom));
    }

    private static void requireText(String value, String name) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(name + " cannot be blank");
        }
    }
}
