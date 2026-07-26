# Automatic Expense Tracker — System Specification (PRD)

## Problem Statement

Managing personal finances across multiple bank accounts, credit cards, digital wallets, cash payments, recurring bill statements, loans, and shared group expenses is fragmented, tedious, and error-prone. Manual expense logging leads to missing transactions, unexpected late fees on credit card bills, uncollected peer debts, and poor visibility into net personal spending. Furthermore, existing expense tracking applications either require compromising privacy with full cloud bank credential sharing, fail to prevent duplicate entries when both SMS and Email receipts arrive, or lack multi-device synchronization across mobile and web interfaces.

## Solution

An intelligent, privacy-first, single-user Personal Financial Management application running across Android mobile devices and desktop web browsers. The solution automatically captures incoming transaction evidence from SMS alerts and real-time Email push webhooks, deterministically deduplicates overlapping events within a ±15-minute window, learns vendor category rules from user corrections, tracks credit card bill lifecycles with auto-reconciliation upon payment, manages peer debt ledgers with installment tracking, monitors formal loans and credit card EMI obligations, and provides rich financial analytics—all backed by an AWS serverless (Java 21 Quarkus + DynamoDB Single-Table + API Gateway) backend and a responsive Flutter frontend.

## User Stories

1. As a mobile user, I want the application to automatically listen for incoming bank and credit card SMS alerts, so that every purchase or credit is recorded instantly without manual data entry.
2. As a desktop user, I want transaction receipts and credit card bill statements sent to my email to be ingested via real-time push webhooks, so that my financial records stay up to date without waiting for manual file uploads or periodic polling.
3. As a financial account owner, I want the system to match SMS and Email transaction events occurring within a ±15-minute window for the same account and amount, so that duplicate expenses are never counted twice.
4. As a user, I want email ingestion to enrich simple SMS records with detailed vendor metadata and itemized receipts, so that I have complete context for every transaction.
5. As a user, I want ambiguous or potential duplicate transactions to be flagged as "Needs Review" with a 1-tap confirmation prompt on my dashboard, so that I retain full control over my financial data.
6. As a user, I want unmapped payee names (such as personal UPI transfers like "saira banu") to be flagged for category assignment, so that I can categorize unrecognized transactions easily.
7. As a user, I want the system to automatically learn vendor category rules whenever I assign a category to an ambiguous payee, so that future transactions from the same payee are categorized automatically.
8. As a user, I want to create and manage financial accounts (Savings Accounts, Credit Cards, Digital Wallets, Cash), so that I can track balances across all my financial entities.
9. As a user, I want to view my credit card bill statement balances, minimum amounts due, and due dates on a unified bill dashboard, so that I never miss a payment deadline.
10. As a user, I want outgoing debit transactions that pay off a credit card bill to automatically reconcile open bill statements from "PENDING" to "PAID", so that my payment status updates automatically.
11. As a user, I want automated push notification reminders sent 5 days, 2 days, and on the due date for upcoming credit card bills and EMI obligations, so that I avoid late fees.
12. As a user, I want a peer-to-peer debt ledger to record money lent to or borrowed from personal contacts, so that I can keep track of informal debts and installment repayments.
13. As a user, I want incoming or outgoing payments linked to a contact to automatically decrement their outstanding debt balance until settled, so that my lending ledger reflects accurate real-time balances.
14. As a user, I want to split a transaction (e.g. a group dinner bill) among multiple contacts, so that their shares automatically populate as peer debt entries while adjusting my net personal expense.
15. As a user, I want to mark a transaction as "100% Lent" (paying on behalf of someone else), so that my net personal expense for that transaction is reduced to $0.00 without skewing my personal spending budgets.
16. As a user, I want to configure formal bank loans (principal, interest rate, tenure, monthly EMI amount, payment due date), so that I can monitor principal reduction and loan timelines over time.
17. As a user, I want bank debit alerts matching my monthly loan EMI to be automatically recognized and credited against my loan balance, so that my loan schedule updates effortlessly.
18. As a user, I want to track credit card purchases converted into monthly installments (EMIs), so that I can see completed vs remaining installments and total monthly committed obligations.
19. As a user, I want to set monthly spending budgets per category or globally, so that I receive progress alerts when my spending reaches 80% or 100% of my target limits.
20. As a user, I want real-time multi-device synchronization via WebSocket connections, so that edits or new transactions on my mobile app immediately update my web browser session and vice versa.
21. As a user, I want offline-first transaction logging on my mobile phone using local storage, so that SMS alerts captured without internet connectivity sync seamlessly once network access is restored.
22. As a user, I want visual financial analytics (cash flow charts, category breakdown pie charts, monthly spending trend graphs), so that I can understand my financial velocity and habits.
23. As a user, I want natural-language AI insights surfacing spending velocity anomalies, subscription price changes, and category trend shifts, so that I can make better spending decisions.
24. As a user, I want to export my transaction history, peer ledgers, and financial reports as CSV or PDF files, so that I can perform offline analysis or tax preparation.
25. As a user, I want device biometric auth (Fingerprint / Face ID) or PIN protection on mobile, and automatic idle session locking on web, so that my personal financial data remains private and secure.

## Implementation Decisions

### Architectural Principles & Layers
- **Hexagonal Architecture (Ports & Adapters)**: The domain core remains completely decoupled from technical frameworks (no Quarkus, AWS SDK, or database annotations in domain entities). High-level domain policies depend on domain ports (interfaces), implemented by infrastructure adapters.
- **Pure Domain Core (`com.automaticexpense.tracker.domain`)**: Contains pure Java domain entities (`Transaction`, `FinancialAccount`, `BillStatement`, `PeerDebtEntry`, `LoanAccount`, `VendorCategoryRule`), value objects, domain invariants, and domain events.
- **Inbound Application Ports (`com.automaticexpense.tracker.application.port.in`)**: Defines use case interfaces (`IngestTransactionUseCase`, `ReconcileBillUseCase`, `ManagePeerDebtUseCase`, `ManageLoanUseCase`, `LearnVendorRuleUseCase`).
- **Outbound Infrastructure Ports (`com.automaticexpense.tracker.application.port.out`)**: Defines persistence interfaces (`TransactionRepository`, `AccountRepository`, `BillRepository`, `PeerDebtRepository`, `LoanRepository`, `VendorRuleRepository`) and notification/sync ports (`ClientSyncPort`, `PushNotificationPort`).

### Technology Stack & Persistence Strategy
- **Backend Stack**: Java 21 with Quarkus framework compiled to GraalVM Native Executables, deployed on AWS Lambda behind Amazon API Gateway (REST APIs and WebSocket API).
- **Database Schema**: AWS DynamoDB Single-Table Design (`ExpenseTrackerData`), using `PAY_PER_REQUEST` billing mode:
  - Partition Key: `PK = USER#<UserId>`
  - Sort Key prefixes: `TXN#<Timestamp>#<TxnId>`, `ACC#<AccountId>`, `CAT#<CategoryId>`, `BILL#<BillId>`, `DEBT#<ContactId>#<DebtId>`, `LOAN#<LoanId>`, `RULE#<PayeeKey>`.
  - Attributes stored as flexible JSON structures to allow zero-migration schema expansion (e.g. future investments).
- **Infrastructure as Code**: Terraform HCL modules under `/terraform` provisioning API Gateway REST/WebSocket endpoints, Lambda handlers, DynamoDB table, SNS/EventBridge topics for Gmail push webhooks, and IAM execution roles.
- **Frontend Stack**: Single Flutter (Dart) codebase under `/frontend` serving Android Mobile (with background SMS `BroadcastReceiver` native channel) and Web Browser interface with responsive Glassmorphic dark mode styling.
- **Offline Storage**: Flutter local offline queue (Isar/SQLite) writing captured SMS events instantly and syncing via background worker to API Gateway upon network reconnection.

## Testing Decisions

### Testing Seams & Protocol
- **Primary Testing Seam (Backend Use Cases)**: Tests will target public **Application Use Case Ports** (`IngestTransactionUseCase`, `ReconcileBillUseCase`, `ManagePeerDebtUseCase`, `ManageLoanUseCase`, `LearnVendorRuleUseCase`). This allows validating end-to-end business rules (deduplication, bill reconciliation, expense splitting, EMI progress, vendor rule learning) without coupling tests to HTTP/AWS infrastructure or internal private methods.
- **Parser Seam (Backend & Mobile)**: Inbound parsers (`SmsTransactionParserTest`, `EmailTransactionParserTest`) will be tested against contract specifications using fast, isolated unit tests.
- **Frontend State Seam**: Flutter BLoC / Service boundaries will be tested using widget and unit tests to verify state transitions and offline sync queues without requiring live backend endpoints.
- **Test-Driven Development (TDD)**: Strictly follow Red → Green → Refactor protocol. Write a failing test first specifying expected domain behavior, implement minimal code to pass, and refactor while maintaining green status.
- **Prior Art**: Building upon existing parser test patterns in `com.automaticexpense.tracker.domain.SmsTransactionParserTest`.
- **Assertions Policy**: All assertion expected values must be derived strictly from domain specs (no tautological assertions or implementation state inspection).

## Out of Scope

- Multi-tenant multi-user accounts (the system is explicitly designed for a single account owner).
- Direct open-banking API credentials or OAuth scraping of bank login portals (ingestion relies on SMS and Email notification webhooks).
- Automated bill payment execution (the app tracks and alerts on bills; actual payment execution occurs in user's banking apps).
- Real-time stock broker trading execution.

## Further Notes

- AWS Always Free tier limits (1M Lambda requests/mo, 25GB DynamoDB, 1M SNS/EventBridge events/mo) strictly guarantee $0.00/month operating cost for single-user activity.
- Future schema extensions (e.g., investment portfolios, mutual fund NAV tracking) are supported via DynamoDB `INV#` sort keys without requiring database migrations.
