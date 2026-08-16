package com.automaticexpense.tracker.domain;

import java.util.Objects;

public class VendorCategoryRule {
    private final String payeeKey;
    private final String rawPayeePattern;
    private final String categoryId;
    private final String payeeNickname;
    private final boolean userDefined;

    public VendorCategoryRule(String payeeKey, String rawPayeePattern, String categoryId, String payeeNickname, boolean userDefined) {
        this.payeeKey = Objects.requireNonNull(payeeKey, "payeeKey cannot be null");
        this.rawPayeePattern = rawPayeePattern != null ? rawPayeePattern : payeeKey;
        this.categoryId = Objects.requireNonNull(categoryId, "categoryId cannot be null");
        this.payeeNickname = payeeNickname;
        this.userDefined = userDefined;
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
        return normalized.contains(this.payeeKey) || this.payeeKey.contains(normalized);
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

    public String payeeNickname() {
        return payeeNickname;
    }

    public boolean isUserDefined() {
        return userDefined;
    }
}
