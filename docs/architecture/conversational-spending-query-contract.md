# Conversational spending-query contract

`POST /v2/finance-queries` accepts:

```json
{
  "question": "How much did I spend at a merchant this month?",
  "currency": "INR",
  "timezone": "Asia/Kolkata",
  "asOf": "2026-08-31T18:30:00Z"
}
```

`currency`, `timezone`, and `asOf` are optional. The authenticated gateway
identity scopes the snapshot; callers must not send a user or account ID.

An answer has `status: "ANSWER"`, a fact classification, deterministic
observation, as-of time, formula ID/version, source count, assumptions,
warnings, and an optional drill-down filter. A request requiring a safer
interpretation has `status: "CLARIFICATION"` and a message. It never returns a
model-generated financial value.

The planner resolves calendar months, registered merchants, categories, and
safe account aliases locally. It can delegate unresolved planning through
`LanguageModelPort`; Gemini receives only a redacted question, the registered
capability names, and opaque aliases (`merchant-1`, `category-1`,
`account-1`). It does not receive the snapshot, transactions, account IDs,
contact names, email content, or ledger identifiers. Any unavailable, invalid,
unknown, or budget-rejected model plan becomes a clarification.

The current `FinanceQueryHandler` deliberately has deterministic-only default
composition. Deployment must inject the managed-secret credential-backed Gemini
adapter, the DynamoDB monthly request reservation, and non-prompt usage
telemetry. The API Gateway route and dashboard navigation must be provisioned
by their owning slices before the Flutter query screen is reachable in a live
application.
