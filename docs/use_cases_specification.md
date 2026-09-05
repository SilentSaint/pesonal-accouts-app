# Automatic Expense Tracker — Use Cases Specification

## 1. Overview & Vision
A single-user personal finance application accessible via a mobile phone app and a desktop web browser. The system helps the user automatically track daily expenses, manage credit card bills, monitor payment due dates, categorize spending, track monthly budgets, and understand their complete financial position through explainable, conversational intelligence grounded in a deterministic financial ledger.

---

## 2. System Actors

* **User**: The single account owner who uses the mobile app and web browser to view, manage, and analyze personal finances.
* **Automatic Ingestion Engine**: The system component responsible for receiving, reading, and processing transaction notifications (text messages and emails).
* **Finance Intelligence Engine**: The system component that selects relevant financial records, invokes deterministic calculations, identifies patterns and risks, produces forecasts and scenarios, and generates explainable answers and proactive insights.

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

### Use Case 12: Finance Intelligence Engine, Analytics & Reports
* **Goal**: Provide the user with deterministic financial analytics, explainable intelligence, visual reports, and downloadable summaries that form the foundation for proactive insights and conversational finance use cases.
* **Primary Flow**:
  1. The system presents visual charts summarizing cash flow (income vs expenses), category spending breakdowns, and monthly trends over time.
  2. The system builds a unified financial state from transactions, accounts, income, budgets, bills, recurring commitments, peer debt, loans, credit card EMIs, goals, assets, liabilities, and explicit user-provided financial context.
  3. Deterministic analysis services calculate totals, comparisons, trends, forecasts, debt positions, net worth, and other financial measures from the ledger.
  4. The Finance Intelligence Engine selects the relevant calculations and evidence to answer questions or generate proactive insights; generative AI may explain results but MUST NOT become the source of financial truth.
  5. Every generated answer or insight distinguishes facts, derived insights, predictions, and recommendations, and includes assumptions, uncertainty, calculation details, and transaction-level evidence where applicable.
  6. The user can export transaction histories, peer ledgers, and financial summaries into standard spreadsheet (CSV) or printable document (PDF) files.

### Use Case 13: Personal Data Security & Access Protection
* **Goal**: Ensure personal financial data remains private and protected on personal devices.
* **Primary Flow**:
  1. On mobile devices, the app requires biometric confirmation (fingerprint / face recognition) or a security PIN whenever the user opens or unlocks the application.
  2. On web browsers, the session automatically locks after a period of inactivity to prevent unauthorized viewing.

### Use Case 14: Finance Intelligence & Conversational Assistant
* **Goal**: Provide a natural-language financial intelligence layer that understands the user's complete financial context and can answer questions, discover patterns, explain changes, identify risks, make projections, and help evaluate financial decisions.
* **Primary Flow**:
  1. The system continuously builds a unified financial context from bank and wallet transactions, credit cards and statements, income, budgets, recurring payments, subscriptions, peer debt, formal loans, credit card EMIs, goals, and explicit user preferences.
  2. The user asks a financial question in natural language, such as "Where did most of my money go this month?", "Can I afford a ₹1 lakh purchase next month?", or "Am I on track with my budget?"
  3. The Finance Intelligence Engine identifies the required accounts, transactions, periods, categories, obligations, calculations, and user context.
  4. Deterministic financial services calculate the answer from the user's ledger and return structured results with supporting records.
  5. The system responds with a direct answer, supporting numbers, relevant comparisons, observations, assumptions or uncertainty, and drill-down links to source transactions.
  6. The user asks follow-up questions without restating previously established conversational context.
* **Intelligence Classification**:
  * **Fact**: A directly calculated or recorded value, such as "You spent ₹42,300 on dining in August."
  * **Derived Insight**: An interpretation calculated from facts, such as "Dining spending is 27% higher than your three-month average."
  * **Prediction**: A forecast with assumptions and uncertainty, such as "At your current pace, you are likely to exceed the dining budget by approximately ₹4,500."
  * **Recommendation**: An optional action derived from stated goals and calculated trade-offs, such as "Reducing restaurant spending by approximately ₹1,500 per week would keep you within the monthly target."
* **Rule**: Predictions and recommendations MUST be labeled and MUST NOT be presented as established facts.

### Use Case 15: Natural-Language Financial Query & Exploration
* **Goal**: Allow the user to interrogate financial data conversationally without navigating multiple dashboards, constructing reports, or knowing internal identifiers.
* **Example Queries**:
  * "Show me everything I spent on Amazon in the last six months."
  * "How much did I spend on transportation compared with last year?"
  * "Which month had my highest expenses?"
  * "What were my five biggest purchases this month?"
  * "How much money did I lend to friends this year, and how much should I receive back?"
  * "How much of my income is already committed to EMIs?"
  * "What bills are coming up in the next 30 days?"
  * "Which credit card costs me the most in interest or fees?"
* **Expected Behavior**:
  1. The system resolves relative periods such as "this month", "last month", "this year", "recently", and "my usual spending" using the user's locale, timezone, history, and conversation context.
  2. The system resolves references such as "that restaurant", "my car loan", and "the money Rahul owes me" against the active conversation and known financial context.
  3. If a reference remains materially ambiguous, the system asks the user to select or clarify the intended entity rather than silently choosing one.
  4. The user is never required to know database terminology, category IDs, account IDs, or reporting-period syntax.
  5. Query results preserve the filters, date range, and source records used so the user can inspect or refine them in a follow-up.

### Use Case 16: Proactive Spending Insights
* **Goal**: Automatically identify meaningful financial changes, anomalies, and positive patterns without requiring the user to ask a question.
* **Primary Flow**:
  1. The Finance Intelligence Engine periodically analyzes newly captured transactions and relevant historical data.
  2. It evaluates changes against the user's own history, budgets, goals, and stated preferences.
  3. It creates concise dashboard insight cards only when a configurable statistical or financial significance threshold is met.
  4. Each insight states the observation, comparison baseline, period, amount or percentage change, and confidence where applicable.
  5. The user can dismiss, correct, or drill into an insight to inspect its calculation and source transactions.
* **Example Insights**:
  * **Spending spike**: "You spent ₹18,400 more than usual on shopping this month."
  * **Category increase**: "Food & Dining is 22% higher than your three-month average."
  * **Behavior change**: "Your average weekend spending has increased 31% over the last two months."
  * **Merchant increase**: "Your spending at Swiggy increased from an average of ₹2,100/month to ₹4,350 this month."
  * **Unusual transaction**: "A ₹24,999 transaction is significantly higher than your typical electronics purchases."
  * **Positive insight**: "You spent ₹7,200 less than your average on discretionary purchases this month."

### Use Case 17: Spending Trend & Personal Benchmark Intelligence
* **Goal**: Help the user understand whether spending is normal for them, not merely how much they spent.
* **System Capabilities**:
  * Calculate current-period and previous-period spending.
  * Calculate rolling averages and year-over-year and month-over-month changes.
  * Calculate percentage change, transaction frequency, and average transaction value.
  * Identify the highest and lowest comparable periods.
  * Determine direction and strength of a spending trend.
  * Apply the same analysis to a category, merchant, account, or spending type.
* **Example**: "You spent ₹31,240 on groceries this month, 12% more than last month and 8% above your six-month average."
* **Rules**:
  1. Every comparison MUST use equivalent periods and disclose the comparison baseline.
  2. A large change MUST NOT be labeled harmful solely because of its size; interpretation must consider historical behavior, known one-time events, budgets, and stated goals.
  3. Partial-period comparisons MUST compare equivalent elapsed portions or clearly state that the period is incomplete.

### Use Case 18: Recurring Expense & Subscription Intelligence
* **Goal**: Discover recurring financial commitments and help the user understand their fixed-cost burden.
* **Primary Flow**:
  1. The system analyzes historical transactions for recurring merchant, amount, and timing patterns.
  2. It proposes a recurring commitment with an estimated cadence, expected amount range, next payment date, and confidence.
  3. It classifies the commitment as a subscription, utility, insurance, EMI, rent, membership, or other recurring obligation.
  4. The user can confirm, correct, ignore, or reclassify the proposed commitment.
  5. The system detects material amount, cadence, or status changes and presents upcoming recurring commitments.
  6. The system calculates monthly and annualized recurring costs and the share of average monthly income committed to them.
* **Example Insights**:
  * "You have 14 recurring subscriptions costing approximately ₹4,280/month."
  * "Netflix increased from ₹649 to ₹799."
  * "This subscription has continued for three months after you marked it as unused."
  * "Your recurring commitments account for 38% of your average monthly income."
* **Rule**: Lack of transaction activity cannot prove lack of service usage; any unused-subscription claim MUST depend on explicit user input or verified usage data.

### Use Case 19: Cash-Flow Forecasting
* **Goal**: Forecast the user's likely future cash position using available cash, expected income, known obligations, and estimated variable spending.
* **Primary Flow**:
  1. The system determines the current available balance for the accounts included in the forecast.
  2. It identifies expected incoming funds and their confidence.
  3. It identifies known future bills, EMIs, subscriptions, debt repayments, goal contributions, and other commitments.
  4. It estimates variable spending from comparable historical periods and known user plans.
  5. It generates a daily or weekly forward projection with best-case, expected, and worst-case ranges where uncertainty is material.
  6. It highlights dates on which projected available cash may fall below zero or below the user's preferred minimum balance.
* **Examples**:
  * "Based on your current spending pattern, your projected available balance at the end of September is approximately ₹62,000."
  * "Your projected balance may fall below your preferred ₹50,000 minimum during the third week of September."
* **Rule**: Every forecast MUST identify its horizon, starting balance, included accounts, known commitments, variable-spending assumption, and data freshness.

### Use Case 20: Budget Intelligence & Forecasting
* **Goal**: Determine whether the user is on track to stay within each budget and explain the drivers of projected over- or underspending.
* **Primary Flow**:
  1. The system calculates actual spend, remaining budget, elapsed time, historical spending pace, and known upcoming commitments for each active budget.
  2. It projects end-of-period spending using comparable historical behavior and current-period evidence.
  3. It classifies the budget as on track, at risk, or projected to exceed its target.
  4. It explains material drivers, including unusual purchases, merchant changes, and recurring obligations.
  5. It updates the projection as new transactions arrive or the user corrects classifications.
* **Example**: For a ₹10,000 grocery budget with ₹6,800 spent after 20 of 30 days, the system may respond: "You're spending faster than your normal pace. At the current rate, you'll likely finish the month around ₹10,900. ₹2,400 of this month's grocery spending came from two unusually large purchases."
* **Rule**: Budget forecasts MUST account for partial periods and MUST distinguish actual spending from projected spending.

### Use Case 21: Goal Planning & Scenario Analysis
* **Goal**: Allow the user to define financial goals and evaluate how savings behavior or hypothetical decisions affect those goals and the broader financial plan.
* **Goal Planning Flow**:
  1. The user defines a goal name, target amount, target date, current allocated savings, priority, and optional linked account.
  2. The system calculates the remaining amount, remaining time, required periodic contribution, current contribution rate, and expected completion date.
  3. The system compares the expected completion date with the target date.
  4. It explains the contribution change required to close any gap.
  5. Progress updates as linked balances or goal contributions change.
* **Example**: For a ₹12,00,000 car goal due in June 2027 with ₹4,00,000 saved, the system may answer: "At your current savings rate, you'll reach ₹12 lakh around September 2027. Saving an additional ₹8,500/month would bring the target forward to June 2027."
* **Scenario Analysis Flow**:
  1. The user proposes a hypothetical change, such as a ₹2 lakh purchase, a 10% salary increase, or an extra ₹10,000 monthly loan payment.
  2. The system copies the relevant current financial state into a non-persistent scenario.
  3. It applies only the stated changes and recalculates cash flow, budgets, debt schedules, and goal completion dates.
  4. It presents the baseline and scenario side by side, including trade-offs, assumptions, and affected goals.
  5. The hypothetical change does not alter the ledger unless the user explicitly converts it into a plan or commitment.

### Use Case 22: Unified Debt Intelligence
* **Goal**: Provide a complete and explainable view of money the user owes and money owed to the user.
* **Debt Position Includes**:
  * Formal loan balances and projected interest.
  * Credit-card statement balances and installment obligations.
  * Peer money borrowed by the user.
  * Peer money lent by the user.
  * Upcoming repayments and repayment progress.
* **Example Questions**:
  * "How much do I owe in total?"
  * "How much money do people owe me?"
  * "Which debt should I pay off first?"
  * "How much interest will I pay on the current schedule?"
  * "What happens if I pay an extra ₹5,000 every month?"
* **Primary Flow**:
  1. The system aggregates liabilities and receivables without netting away the gross totals.
  2. It displays itemized balances, rates, due dates, monthly commitments, and repayment progress.
  3. It calculates the net debt position as total liabilities minus collectible receivables.
  4. For payoff comparisons, it calculates each strategy deterministically and states the optimization objective, such as minimum interest or earliest debt-free date.
  5. The system presents debt payoff suggestions as recommendations, not financial facts or guarantees.

### Use Case 23: Explainable Financial Health Score
* **Goal**: Provide a simple high-level view of financial health using a transparent, versioned scoring model with traceable drivers.
* **Score Inputs**:
  * Savings rate.
  * Emergency-cash coverage.
  * Debt-to-income ratio.
  * Fixed-cost ratio.
  * Budget adherence.
  * Credit-card utilization.
  * Recurring commitments.
  * Cash-flow stability.
  * Progress toward goals.
* **Primary Flow**:
  1. The system calculates each available component using disclosed formulas, periods, weights, and source data.
  2. It omits unavailable components rather than inventing values and discloses how missing data affects the result.
  3. It produces an overall score and lists positive drivers, watch items, and changes since the previous score.
  4. The user can inspect every component and its underlying records.
* **Example**: "Financial Health: 78/100. Strengths: savings rate increased to 24%, no missed payments, and emergency cash covers 4.2 months. Watch: credit-card EMI commitments increased 18%, and dining spending is above target."
* **Rule**: The score MUST NOT be represented as a credit score, professional financial assessment, or unexplained "AI score."

### Use Case 24: Financial Anomaly & Risk Detection
* **Goal**: Detect transactions and financial situations that deserve the user's attention while minimizing false certainty.
* **Detected Conditions**:
  * Potential duplicate transactions not resolved during ingestion.
  * A merchant not previously seen in the user's history.
  * A transaction materially larger than comparable transactions.
  * A budget likely to be exceeded.
  * A cluster of large payments or insufficient projected cash.
  * Unexpected changes to recurring amounts or cadence.
* **Primary Flow**:
  1. The system evaluates each condition using deterministic rules or a versioned statistical model.
  2. It assigns a reason, severity, confidence, and comparison baseline.
  3. It alerts the user only when the configured threshold is met.
  4. The user inspects the supporting transactions and marks the alert as valid, expected, incorrect, or resolved.
  5. Corrections improve user-specific rules without changing historical facts.
* **Example Alerts**:
  * "These two ₹8,499 transactions may be duplicates."
  * "This merchant has not appeared in your transaction history before."
  * "This transaction is 4.8× your typical transaction size."
  * "At your current spending rate, your entertainment budget is likely to be exceeded."
  * "Three large payments totaling ₹74,000 are due within the next 12 days."

### Use Case 25: Net Worth Intelligence
* **Goal**: Track the user's overall financial position over time and explain the drivers of change.
* **Primary Flow**:
  1. The system aggregates assets from account balances, cash, investments, and manually recorded assets.
  2. It aggregates liabilities from formal loans, credit-card obligations, and peer debt owed by the user.
  3. It calculates net worth as total assets minus total liabilities at a stated point in time.
  4. It stores periodic snapshots and compares net worth across equivalent dates.
  5. It attributes changes to contributions, withdrawals, market-value changes, debt repayments, new liabilities, and corrections where the available data supports that attribution.
* **Example**: "Your net worth increased by ₹82,000 this month: ₹50,000 from investment appreciation and ₹42,000 from savings, offset by ₹10,000 of additional loan liability."
* **Rules**:
  1. Every net worth result MUST state its valuation date, included and excluded assets and liabilities, and stale balances.
  2. Peer receivables MAY be shown separately but MUST NOT be counted as a collectible asset without clearly disclosing that assumption.

### Use Case 26: Investment Intelligence (Optional)
* **Goal**: Provide analytical context about the user's investments without presenting the system as an investment adviser.
* **Capabilities**:
  * Portfolio allocation by asset class.
  * Asset and issuer concentration.
  * Historical portfolio value.
  * Contribution and withdrawal tracking.
  * Investment-to-cash allocation.
  * Equity and exchange-traded fund exposure.
  * Portfolio changes and basic scenarios.
* **Examples**:
  * "Your portfolio is 72% equities, 18% debt, and 10% cash."
  * "Your equity exposure increased from 61% to 72% over the past year."
* **Rules**:
  1. Valuations MUST state price source and timestamp.
  2. Missing or stale market data MUST be disclosed.
  3. Analysis MUST distinguish historical facts and hypothetical scenarios from recommendations and MUST NOT execute trades.

### Use Case 27: Personal Financial Memory & Context
* **Goal**: Let the user explicitly record financial facts and preferences that cannot be derived reliably from transaction history.
* **Example Context**:
  * "I'm saving for a car next year."
  * "I want to keep at least ₹50,000 in my checking account."
  * "Rahul is my brother."
  * "The ₹20,000 payment to Priya was repayment of a personal loan."
  * "I split rent with my partner."
* **Primary Flow**:
  1. The user creates a financial context item or explicitly asks the assistant to remember one.
  2. The system shows the normalized fact, its intended scope, and where it will be used before saving it.
  3. The system uses active context items in relevant analyses, forecasts, reference resolution, and recommendations.
  4. The user can view, edit, deactivate, or permanently delete every context item.
  5. Answers identify when a context item materially affected a result.
* **Rules**:
  1. The system MUST NOT silently persist inferred personal facts as financial memory.
  2. Stored context MUST remain separate from immutable ledger facts and include provenance and timestamps.
  3. Deleting a context item prevents future use without rewriting historical transactions or previously generated snapshots.

### Use Case 28: Explainable & Auditable Financial Intelligence
* **Goal**: Make every intelligent answer, forecast, score, anomaly, and recommendation auditable.
* **Primary Flow**:
  1. The user opens "How was this calculated?" or asks which data was used.
  2. The system displays the direct answer and classifies it as a fact, derived insight, prediction, or recommendation.
  3. It displays the calculation formula, aggregated values, record count, date range, filters, comparison baseline, assumptions, confidence, and data freshness.
  4. It links to the exact source transactions, balances, commitments, goals, or context items used.
  5. The user can correct a category, merchant, recurrence, context item, or other source record.
  6. The system recalculates affected results while retaining an audit record of the correction.
* **Example Explanation**:
  * **Answer**: "You spent ₹36,420 on dining this month."
  * **Calculation**: 47 transactions across 12 merchants totaling ₹36,420.
  * **Compared with**: Three-month average of ₹28,750; change of +26.7%.
  * **Evidence**: "View 47 transactions."
* **Rule**: A natural-language explanation MUST be generated from the structured calculation result and evidence set; it MUST NOT introduce unsupported amounts, causes, or records.

### Use Case 29: "Ask My Finances" — Unified Finance Copilot
* **Goal**: Provide one conversational interface through which the user can access every part of the personal finance system.
* **Primary Flow**:
  1. The user opens "Ask My Finances" and asks a broad or specific financial question.
  2. The system combines relevant ledger facts, financial state, deterministic intelligence capabilities, and explicit financial context.
  3. It presents a concise answer with prioritized observations and expandable evidence.
  4. The user continues with follow-up questions, opens a drill-down, corrects source data, or starts a scenario without switching to a specialized report.
  5. When the requested capability or data is unavailable, the system states the limitation instead of fabricating an answer.
* **Example Conversation**:
  * **User**: "How am I doing financially this month?"
  * **System**: "Your income is ₹1,85,000 and your expenses are ₹1,12,400, leaving ₹72,600 available so far. Spending is 8% higher than your three-month average, mainly due to travel and shopping. You are on track to remain within your overall monthly budget, but dining is running 23% above its normal pace. You have ₹38,000 of upcoming bills and ₹24,000 of EMI commitments before month-end. At your current spending rate, your projected month-end surplus is approximately ₹61,000."
  * **Follow-ups**: "Why did spending increase?", "Can I afford ₹50,000 next month?", "What can I cut?", "How much do I owe?", or "What if I pay ₹10,000 extra toward my loan?"

---

## 4. Finance Intelligence Architecture

The application separates deterministic financial records and calculations from AI-assisted explanation. The Finance Intelligence Engine may select tools, resolve conversational intent, and present results, but it MUST NOT create or alter ledger facts without an explicit domain command and validation.

### Layer 1 — Financial Data Foundation
* Transaction ingestion from SMS, email, manual entry, and import.
* Reconciliation and duplicate prevention.
* Vendor mapping, accounts, categories, bills, loans, EMIs, and peer debt.

### Layer 2 — Financial State
* Budgets, recurring expenses, subscriptions, cash flow, net worth, debt position, goals, and financial commitments.
* User-confirmed financial context and preferences stored separately from ledger facts.

### Layer 3 — Finance Intelligence
* Natural-language query planning over read-only financial data.
* Trend and anomaly detection.
* Cash-flow and budget forecasting.
* Goal planning and scenario analysis.
* Debt strategy comparison.
* Proactive insights and transparent financial-health analysis.

### Layer 4 — Finance Copilot Experience
* "Ask My Finances" conversation.
* Proactive insight cards and financial dashboards.
* Drill-down explanations and transaction-level evidence.
* Visible, editable, and deletable financial context.

### Cross-Cutting Intelligence Rules
1. **Deterministic source of truth**: Ledger records and versioned financial calculators produce all monetary values used in answers.
2. **Read-only by default**: Questions and scenarios do not mutate financial records. Any mutation requires an explicit user command, domain validation, and confirmation appropriate to its impact.
3. **Point-in-time consistency**: Each answer uses a consistent financial snapshot and identifies its data freshness.
4. **Explainability**: Every result preserves its calculation, filters, assumptions, model or rule version, and evidence references.
5. **Uncertainty**: Forecasts and inferred patterns disclose confidence, ranges, missing data, and assumptions.
6. **Correctability**: Users can correct classifications and context; dependent intelligence is recalculated from the corrected source.
7. **Privacy and control**: Financial context is explicit, purpose-limited, visible, editable, and deletable.
8. **No silent professional advice**: Recommendations are labeled, explain their objective and trade-offs, and do not claim guaranteed outcomes.




