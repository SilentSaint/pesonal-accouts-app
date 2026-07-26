# Automatic Expense Tracker — Use Cases Specification

## 1. Overview & Vision
A single-user personal finance application accessible via a mobile phone app and a desktop web browser. The system helps the user automatically track daily expenses, manage credit card bills, monitor payment due dates, categorize spending, track monthly budgets, and gain smart financial insights into spending habits.

---

## 2. System Actors

* **User**: The single account owner who uses the mobile app and web browser to view, manage, and analyze personal finances.
* **Automatic Ingestion Engine**: The system component responsible for receiving, reading, and processing transaction notifications (text messages and emails).

---

## 3. Business Use Cases

### Use Case 1: Automatic Transaction Capture from Mobile Messages
* **Goal**: Automatically capture financial transactions whenever a bank or card issuer sends a text message alert to the user's mobile phone.
* **Preconditions**: The user has enabled message listening permissions for the mobile application.
* **Primary Flow**:
  1. The user makes a purchase or receives funds using a bank account, credit card, or digital wallet.
  2. The financial institution sends a transaction text message alert to the user's phone.
  3. The system automatically detects the incoming transaction message.
  4. The system extracts key details: monetary amount, merchant/vendor name, payment account (e.g. card ending in 1234), timestamp, and transaction type (expense vs income).
  5. The system records the transaction and automatically updates the user's financial dashboard on both mobile and web browser.

### Use Case 2: Real-Time Transaction & Statement Capture from Email
* **Goal**: Instantly capture transaction receipts and monthly credit card bill statements as soon as they arrive in the user's email inbox without waiting for periodic background polling.
* **Preconditions**: The user has authorized the system to receive real-time notification alerts from one or more linked email accounts.
* **Primary Flow**:
  1. A bank, card issuer, or merchant sends a transaction receipt or monthly credit card bill statement email to the user's linked inbox.
  2. The email service provider instantly notifies the application's ingestion engine the moment the message arrives.
  3. **For Transaction Receipts**: The system reads the incoming message body/attachment and extracts key details: monetary amount, merchant/vendor name, payment account identifier (e.g. card ending in 1234), and timestamp.
  4. **For Credit Card Statements**: The system reads the statement document and extracts key billing details: total statement balance, minimum payment due, payment due date, and credit card identifier.
  5. The system records the transaction or bill statement and immediately updates the user's financial dashboard on both mobile app and web browser.

### Use Case 3: Smart Reconciliation & Duplicate Prevention
* **Goal**: Prevent double-counting when the same purchase triggers both a text message alert and an email notification.
* **Preconditions**: Transaction notifications have been ingested from text messages or emails.
* **Primary Flow**:
  1. The system compares incoming transaction notifications against existing recorded transactions.
  2. If a text message and an email refer to the same payment account, exact monetary amount, and occur within a close timestamp window (e.g. 15 minutes), the system automatically merges them into a single canonical expense entry.
  3. The system enriches the merged expense entry with detailed vendor information or itemized receipt details obtained from the email.
  4. If the system detects two similar transactions with slight ambiguities (e.g., identical purchase amounts near each other), it flags the record as "Needs Review" and surfaces a 1-tap confirmation prompt to the user on the dashboard.

### Use Case 4: Smart Vendor Mapping & Custom Category Learning
* **Goal**: Enable the system to handle unmapped, ambiguous, or personal payee names by flagging them for user review and learning automatic categorization rules for all future transactions.
* **Preconditions**: A transaction notification has been captured, but the payee/vendor name cannot be categorized automatically with high confidence (e.g. money sent to a personal name like `saira banu`).
* **Primary Flow**:
  1. The system ingests a transaction containing an unrecognized or ambiguous payee name (e.g., `50 INR paid to saira banu`).
  2. Because no existing rule or pattern matches `saira banu`, the system flags the transaction as "Uncategorized / Needs Review" on the user's dashboard.
  3. The user opens the transaction, selects the appropriate category (e.g., `Food & Dining > Tea & Snacks`), and optionally enters a vendor nickname (e.g., `Local Tea Vendor`).
  4. The system saves this category mapping rule for the payee `saira banu`.
  5. **Future Automated Flow**: When any future transaction containing the payee `saira banu` is ingested, the system automatically assigns it to `Food & Dining > Tea & Snacks` without requiring user intervention.

### Use Case 5: Peer-to-Peer Debt & Lending Tracking (Borrowing & Lending Ledger)
* **Goal**: Track money lent to or borrowed from contacts (friends, family, colleagues), supporting lump-sum or installment repayments over time.
* **Primary Flow**:
  1. **Creating a Record**: The user records a peer transaction (e.g., "Lent $100 to Rahul" or "Borrowed $200 from Priya").
  2. **Linking Auto-Captured Payments**: When an incoming payment from Rahul or an outgoing payment to Priya is captured via message or email, the user links it to that contact's balance (or accepts the system's smart suggestion).
  3. **Installment & Settlement Progress**: The system updates the outstanding balance after each payment (e.g., "Rahul: Paid $40 of $100 -> Remaining balance owed to you: $60").
  4. **Completion**: Once total repayments match the original amount, the ledger automatically marks the debt as "Fully Settled".

### Use Case 6: Formal Loan Account & EMI Auto-Recognition
* **Goal**: Track formal bank loans (Personal Loans, Home Loans, Car Loans), monitor interest vs principal progress, and recognize recurring monthly EMI debits automatically.
* **Primary Flow**:
  1. **Loan Configuration**: The user inputs basic loan parameters: Total Loan Amount, Annual Interest Rate, Total Tenure (months), Monthly EMI Amount, and Recurring Payment Date.
  2. **Automated EMI Recognition**: When the monthly bank debit message for the EMI is captured, the system automatically matches the transaction to the loan account.
  3. **Progress Update**: The system updates the elapsed loan timeline (e.g. "Month 14 of 36 Paid"), calculates the remaining principal balance, and updates the next payment due date.
  4. **EMI Reminders**: Sends reminder notifications before upcoming EMI due dates.

### Use Case 7: Credit Card Installment (EMI) Schedule Management
* **Goal**: Track credit card purchases that have been converted into monthly installments, monitoring completed vs remaining installments and total monthly committed obligations.
* **Primary Flow**:
  1. **Tagging an Expense as EMI**: When a credit card purchase is split into monthly installments (e.g., 6-month EMI for a laptop), the user tags the transaction with installment duration details.
  2. **Monthly Statement & Message Matching**: As monthly credit card statement emails or SMS alerts arrive, the system tracks installment progress (e.g., "Installment 3 of 6 Paid").
  3. **Monthly Commitment View**: Displays total monthly committed credit card EMI obligations across all cards to help the user plan upcoming spending safely.

### Use Case 8: Expense Splitting & 100% Full-Amount Lending
* **Goal**: Allow the user to split an auto-captured or manual transaction among multiple contacts or assign 100% of a transaction as money lent to a specific contact.
* **Preconditions**: A transaction has been captured or manually created.
* **Primary Flow**:
  * **Scenario A: Partial Group Split**:
    1. The user selects a transaction (e.g. 1,000 INR restaurant bill) and chooses "Split Expense".
    2. The user selects contacts (e.g., Rahul, Priya, and Amit).
    3. The system divides the bill (e.g. 250 INR each for 4 people including the user).
    4. The system creates peer debt records for Rahul (250 INR), Priya (250 INR), and Amit (250 INR) under their respective debt ledgers, and adjusts the user's net personal expense for this bill from 1,000 INR down to 250 INR.
  * **Scenario B: 100% Full-Amount Lending (Paying on Behalf of Someone)**:
    1. The user pays for a transaction entirely on behalf of someone else (e.g. 500 INR movie ticket for a friend).
    2. The user selects the transaction, taps "Mark as 100% Lent", and selects the contact.
    3. The system assigns 100% of the transaction amount (500 INR) to that contact's debt ledger as money owed to the user.
    4. The system reduces the user's net personal expense for this transaction to 0 INR so it does not distort personal category budgets or cash flow charts.
  * **Settlement**: As incoming payments from contacts arrive via text messages or emails, the user reconciles them against their debt ledger balances until fully settled.

### Use Case 9: Category & Monthly Budget Management
* **Goal**: Organize spending by accounts and categories, and track progress against monthly spending limits.
* **Primary Flow**:
  1. The user defines their financial accounts (e.g., Savings Account, Credit Cards, Cash, Digital Wallets).
  2. The user sets up spending categories and subcategories (e.g., "Food & Dining > Restaurants", "Transportation > Fuel").
  3. As transactions are captured, the system automatically assigns them to the appropriate category based on merchant patterns and learned vendor rules.
  4. The user sets monthly spending targets per category or globally.
  5. The system displays visual progress meters indicating remaining budget and alerts the user when spending reaches target thresholds (e.g., 80% or 100% of budget).

### Use Case 10: Credit Card Bill & Due Date Tracking
* **Goal**: Remind the user of upcoming credit card due dates and automatically track when bills are paid.
* **Preconditions**: A credit card bill statement has been ingested.
* **Primary Flow**:
  1. The system displays the statement balance, minimum payment due, and due date on the user's bill dashboard.
  2. As the due date approaches, the system sends friendly reminder notifications to the user (e.g., 5 days before, 2 days before, and on the due date).
  3. When the user pays the credit card bill, the system detects the outgoing payment transaction from the bank.
  4. The system automatically reconciles the payment against the open bill statement and updates its status from "Pending" to "Paid".

### Use Case 11: Seamless Multi-Device Synchronization
* **Goal**: Ensure the user has access to identical, up-to-date financial data whether viewing on a smartphone or a computer web browser.
* **Primary Flow**:
  1. Any action taken or transaction captured on the mobile device immediately reflects on the web browser interface.
  2. Any edits, budget adjustments, or ledger updates made on the web browser instantly update on the mobile app.

### Use Case 12: Financial Analytics, Insights & Reports
* **Goal**: Provide the user with visual reports, smart observations, and downloadable financial summaries.
* **Primary Flow**:
  1. The system presents visual charts summarizing cash flow (income vs expenses), category spending breakdowns, and monthly trends over time.
  2. The system analyzes spending patterns and generates natural-language observations (e.g., highlighting unusual spending spikes, subscription price increases, or recurring bills).
  3. The user can export transaction histories, peer ledgers, and financial summaries into standard spreadsheet (CSV) or printable document (PDF) files.

### Use Case 13: Personal Data Security & Access Protection
* **Goal**: Ensure personal financial data remains private and protected on personal devices.
* **Primary Flow**:
  1. On mobile devices, the app requires biometric confirmation (fingerprint / face recognition) or a security PIN whenever the user opens or unlocks the application.
  2. On web browsers, the session automatically locks after a period of inactivity to prevent unauthorized viewing.






