# 3. DynamoDB Single-Table Design with Flexible Schema Strategy

Date: 2026-07-26

## Status

Accepted

## Context

The automatic expense tracker requires a database model that supports diverse domain concepts (Transactions, Accounts, Hierarchical Categories, Credit Card Bills, Peer Debt Ledgers, Formal Loans, Vendor Rules) while remaining 100% cost-optimized ($0.00/month) and flexible for future entity additions (e.g. investment tracking, stock/mutual fund portfolios).

Options evaluated:
1. Single-Table Design with generic Partition Key (`PK`), Sort Key (`SK`), and extensible JSON attributes.
2. Multi-Table Design with individual DynamoDB tables per entity type.

## Decision

We chose **Single-Table Design** using a single DynamoDB table named `ExpenseTrackerData`.

### Schema Conventions
* **Table Name**: `ExpenseTrackerData`
* **Billing Mode**: `PAY_PER_REQUEST` (On-Demand, ensuring $0 cost for single-user activity) or Minimal Provisioned (1 RCU / 1 WCU within 25 RCU/WCU Always Free limit).
* **Primary Key**: `PK` (String) - `USER#<UserId>`
* **Sort Key**: `SK` (String) - Entity type prefix + identifier/timestamp:
  * Transactions: `TXN#<Timestamp>#<TxnId>`
  * Accounts: `ACC#<AccountId>`
  * Categories: `CAT#<CategoryId>`
  * Bills: `BILL#<BillId>`
  * Peer Debts: `DEBT#<ContactId>#<DebtId>`
  * Formal Loans: `LOAN#<LoanId>`
  * Vendor Rules: `RULE#<PayeeKey>`
  * **Future Entities (e.g. Investments)**: `INV#<AssetId>` or `PORTFOLIO#<PortfolioId>`
* **Extensibility**: All items store attributes as flexible JSON documents, allowing new fields (such as investment ticker, NAV, quantity, return rates) to be added without table migrations or schema alteration.

## Consequences

### Positive
* **Future-Proof Flexibility**: Adding investments or asset tracking in the future requires zero database migrations—new items simply use the `INV#` sort key prefix.
* **Maximum Cost Efficiency**: Uses 1 single table under DynamoDB Always Free Tier ($0.00/month).
* **Simple Maintenance**: One table to backup, restore, or export via Terraform IaC.

### Negative / Trade-offs
* Query filters rely on application-level filtering for complex multi-attribute searches, which is perfectly suited for single-user data volumes.
