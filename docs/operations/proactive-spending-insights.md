# Proactive Spending Insights

## Public seams

`RefreshFinancialProjectionsUseCase` calculates `ProactiveInsight` cards from
canonical debit transactions and persists them through `ProactiveInsightRepository`.
It only publishes `INSIGHT_UPSERTED` after a new card commits. `ManageProactiveInsightsUseCase`
lists active cards or the user's dismissed history and dismisses a card.

Cards are derived insights, never ledger facts. They expose an as-of timestamp,
formula ID/version, baseline, confidence, assumptions, warnings, filters, and
transaction-level evidence. The current formula requires three non-empty
comparable prior months and both a 25% and INR 500 change. An unusual purchase
must be at least three times the user's category median across three prior
purchases. These thresholds deliberately suppress sparse-history and merely
large changes.

## Persistence and event delivery

Cards use `PK=USER#<user>` and
`SK=INSIGHT#<CreatedAt>#<InsightId>`. A transactional companion record,
`INSIGHT_DEDUP#<deduplicationKey>`, prevents duplicate cards and WebSocket
notifications on SQS retries. Expired cards are excluded from the current
feed; dismissed cards are available using `GET /v2/insights?includeDismissed=true`.

The intended stream trigger accepts only `INSERT` or `MODIFY` images where
`entityType=TRANSACTION` and `SK` begins `TXN#`; it rejects `INSIGHT#` and every
other derived entity prefix. `CanonicalTransactionInsightEnqueuer` also
defensively repeats that check and sends only scope, currency, timestamp, and
event ID to the refresh queue—never raw financial records.

## Frontend integration

`ProactiveInsightsScreen` loads the authoritative `GET /v2/insights` state on
entry and supports pull-to-refresh, error retry, empty/insufficient-history,
and dismissed-history states. It is registered at `/insights`. The dashboard
must navigate to this route and reload this feed after `INSIGHT_UPSERTED`; that
shared dashboard integration is intentionally outside this issue's permitted
file ownership.

## Deployment dependency

`terraform/proactive_insights.tf` provisions the event-source mapping, insight
queue/DLQ, Lambdas, roles and permissions, HTTP routes, EventBridge daily
schedule, and DLQ alarm. `ExpenseTrackerData` must still enable `NEW_IMAGE`
DynamoDB Streams in `terraform/main.tf`. The table resource is explicitly
excluded from this implementation's ownership, so Terraform cannot be applied
until its owner makes that one shared-resource change.
