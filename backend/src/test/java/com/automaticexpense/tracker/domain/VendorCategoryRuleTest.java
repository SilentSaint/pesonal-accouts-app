package com.automaticexpense.tracker.domain;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class VendorCategoryRuleTest {

    @Test
    void shouldNormalizeRawPayeeKeyCorrectly() {
        String rawPayee1 = "Saira Banu  ";
        String rawPayee2 = "SAIRA BANU!";

        String key1 = VendorCategoryRule.normalizePayeeKey(rawPayee1);
        String key2 = VendorCategoryRule.normalizePayeeKey(rawPayee2);

        assertThat(key1).isEqualTo("saira banu");
        assertThat(key2).isEqualTo("saira banu");
    }

    @Test
    void shouldMatchRawPayeeAgainstRule() {
        VendorCategoryRule rule = new VendorCategoryRule(
            "saira banu",
            "Saira Banu",
            "Food & Dining",
            "Tea & Snacks",
            true
        );

        assertThat(rule.matches("saira banu info: upi")).isTrue();
        assertThat(rule.matches("Starbucks")).isFalse();
    }
}
