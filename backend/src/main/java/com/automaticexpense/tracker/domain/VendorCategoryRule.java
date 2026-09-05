package com.automaticexpense.tracker.domain;

import java.util.Objects;

public final class VendorCategoryRule {
    private final String payeeKey;
    private final String rawPayeePattern;
    private final String categoryId;
    private final String subCategory;
    private final String payeeNickname;
    private final boolean userDefined;

    public VendorCategoryRule(
        String payeeKey,
        String rawPayeePattern,
        String categoryId,
        String subCategory,
        String payeeNickname,
        boolean userDefined
    ) {
        this.payeeKey = requireNormalizedPayeeKey(payeeKey);
        this.rawPayeePattern = rawPayeePattern != null && !rawPayeePattern.isBlank()
            ? rawPayeePattern.trim()
            : this.payeeKey;
        this.categoryId = requireText(categoryId, "categoryId");
        this.subCategory = optionalText(subCategory);
        this.payeeNickname = payeeNickname;
        this.userDefined = userDefined;
    }

    public static VendorCategoryRule fromCorrection(
        String rawPayee,
        String categoryId,
        String subCategory,
        String payeeNickname
    ) {
        String payeeKey = normalizePayeeKey(rawPayee);
        return new VendorCategoryRule(
            payeeKey, rawPayee, categoryId, subCategory, payeeNickname, true
        );
    }

    public static String normalizePayeeKey(String rawPayee) {
        if (rawPayee == null || rawPayee.isBlank()) {
            return "unknown";
        }
        return rawPayee.replaceAll("[^a-zA-Z0-9\\s]", "")
            .replaceAll("\\s+", " ")
            .trim()
            .toLowerCase();
    }

    public boolean matches(String rawPayee) {
        if (rawPayee == null) return false;
        String normalized = normalizePayeeKey(rawPayee);
        return !"unknown".equals(normalized)
            && (normalized.contains(this.payeeKey) || this.payeeKey.contains(normalized));
    }

    public String payeeKey() {
        return payeeKey;
    }

    public String rawPayeePattern() {
        return rawPayeePattern;
    }

    public String categoryId() {
        return categoryId;
    }

    public String subCategory() {
        return subCategory;
    }

    public String payeeNickname() {
        return payeeNickname;
    }

    public boolean isUserDefined() {
        return userDefined;
    }

    private static String requireNormalizedPayeeKey(String payeeKey) {
        String normalized = normalizePayeeKey(Objects.requireNonNull(payeeKey, "payeeKey cannot be null"));
        if ("unknown".equals(normalized)) {
            throw new IllegalArgumentException("payeeKey must identify a payee");
        }
        return normalized;
    }

    private static String requireText(String value, String field) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(field + " cannot be blank");
        }
        return value.trim();
    }

    private static String optionalText(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }
}
