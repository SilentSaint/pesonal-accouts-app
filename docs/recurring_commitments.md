# Recurring commitment detection and confirmation

FIE-06 keeps inferred payment patterns separate from the ledger and from user-confirmed obligations.

## Lifecycle

1. Reviewed, canonical debit transactions are grouped by normalized merchant, account, and currency.
2. At least two occurrences with a deterministic weekly, biweekly, monthly, quarterly, or yearly cadence create a `CANDIDATE`.
3. A candidate records its supporting transaction IDs, cadence, minimum/maximum expected amount, next payment date, and confidence. It does not affect fixed-cost calculations.
4. Only the user can confirm, ignore, cancel, restore, or correct a detected commitment. These decisions never modify canonical transactions.
5. Active bills, loans, and card EMIs are projected into the unified list as authoritative commitments. Loan and card-EMI merchant matches are excluded from inferred candidates, preventing duplicate obligations.

`LATE` and `MISSED` are derived from the expected next payment date and cadence-specific grace window. A non-singleton expected amount range is labeled `VARIABLE_AMOUNT`; variable commitments are reported separately and excluded from the fixed-cost ratio.

## Persistence

Detected and user-managed commitments are stored in `ExpenseTrackerData` under:

```text
PK = USER#<verified-principal>
SK = RECUR#<commitment-id>
```

The API adapter derives the partition from the verified API Gateway subject. The client never supplies a user identifier.

## HTTP contract

All routes require a verified gateway identity:

* `GET /v2/recurring-commitments?asOf=YYYY-MM-DD` detects refreshable candidates and returns the unified view.
* `POST /v2/recurring-commitments` creates a user-confirmed commitment.
* `PUT /v2/recurring-commitments/{id}` corrects a confirmed detected commitment.
* `POST /v2/recurring-commitments/{id}/{confirm|ignore|cancel|restore}` records a user decision.
* `GET /v2/recurring-commitments/summary?currency=INR&asOf=YYYY-MM-DD` returns the `fixed-cost-ratio/v1` derived insight.

The summary includes `asOf`, formula ID, `DERIVED_INSIGHT` classification, fixed and variable monthly costs, confirmed fixed monthly income, source counts, and warnings. It reports no ratio when confirmed fixed recurring income is unavailable.
