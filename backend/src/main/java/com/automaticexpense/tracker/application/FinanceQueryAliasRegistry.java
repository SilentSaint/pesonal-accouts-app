package com.automaticexpense.tracker.application;

import com.automaticexpense.tracker.domain.FinanceQueryAlias;
import com.automaticexpense.tracker.domain.FinanceQueryAliasType;
import com.automaticexpense.tracker.domain.FinanceQueryAliases;
import com.automaticexpense.tracker.domain.FinancialSnapshot;
import com.automaticexpense.tracker.domain.Transaction;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

public final class FinanceQueryAliasRegistry {

    public FinanceQueryAliases register(FinancialSnapshot snapshot) {
        List<FinanceQueryAlias> aliases = new ArrayList<>();
        Set<String> merchants = new LinkedHashSet<>();
        Set<String> categories = new LinkedHashSet<>();
        Set<String> accounts = new LinkedHashSet<>();
        for (Transaction transaction : snapshot.canonicalTransactions()) {
            merchants.add(transaction.merchantName());
            if (transaction.categoryId() != null && !transaction.categoryId().isBlank()) {
                categories.add(transaction.categoryId());
            }
            accounts.add(transaction.accountId().value());
        }
        add(aliases, FinanceQueryAliasType.MERCHANT, merchants, true);
        add(aliases, FinanceQueryAliasType.CATEGORY, categories, true);
        add(aliases, FinanceQueryAliasType.ACCOUNT, accounts, false);
        return new FinanceQueryAliases(aliases);
    }

    private void add(
        List<FinanceQueryAlias> destination,
        FinanceQueryAliasType type,
        Set<String> values,
        boolean mayBeSpoken
    ) {
        List<String> sorted = values.stream().sorted(Comparator.naturalOrder()).toList();
        for (int index = 0; index < sorted.size(); index++) {
            String value = sorted.get(index);
            destination.add(new FinanceQueryAlias(
                type,
                type.name().toLowerCase() + "-" + (index + 1),
                value,
                mayBeSpoken ? List.of(value) : List.of("account " + (index + 1))
            ));
        }
    }
}
