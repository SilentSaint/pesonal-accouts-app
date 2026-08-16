# Phone Installation & 30-Day Historical Backfill Verification Guide

## Full-Stack Phone Readiness & 30-Day SMS/Email Account Discovery

This guide details the step-by-step instructions to verify the backend test suite, run the 30-day historical SMS/Email backfill engine, build the Android APK, and install the app on your personal phone.

---

## 1. Backend Layer Verification (`/backend`)

Navigate to the backend directory:

```bash
cd backend
```

Execute the full Java 21 backend test suite:

```bash
./gradlew test
```

### Verified Seams & Test Suites

1. **`AccountDiscoveryEngineTest`**: Verifies 30-day historical SMS and Email event aggregation, account auto-discovery by account last 4 digits (`A/C **1234`), and ±15m window deduplication.
2. **`VendorCategoryRuleTest`**: Verifies payee key normalization and vendor category rule matching logic.
3. **`IngestTransactionUseCaseTest`**: Verifies end-to-end 30-day historical backfill execution, rule-based category learning, SMS & Email dual-channel deduplication, and 1-tap review resolution.

---

## 2. Infrastructure Layer Verification (`/terraform`)

Navigate to the terraform directory:

```bash
cd terraform
```

Validate HCL syntax and configuration:

```bash
terraform fmt -check
terraform validate
```

### Provisioned Resources
- `aws_dynamodb_table.expense_tracker_data`: Single-table persistence supporting `RULE#`, `BILL#`, `DEBT#`, `LOAN#`, and `CAT#` partition patterns.
- `aws_sns_topic.gmail_ingestion_webhook`: Gmail webhook push notification topic.
- `aws_sns_topic.budget_alerts_topic`: 80% and 100% budget threshold alert notification topic.
- `aws_cloudwatch_event_rule.gmail_push_event_rule`: EventBridge rule for real-time email ingestion.

---

## 3. Frontend & Personal Phone Installation (`/frontend`)

### Run Locally on Browser (Firefox / Web Server)
```bash
cd frontend
export PATH="$PATH:/home/rakshith/flutter/flutter/bin"
flutter run -d web-server --web-port=8080
```
Open `http://localhost:8080` in **Firefox** or any web browser!

### Build Installable Android APK for Personal Phone

To build the APK for your personal Android phone:

```bash
cd frontend
export PATH="$PATH:/home/rakshith/flutter/flutter/bin"
flutter build apk --debug
```

The compiled APK will be located at:
```text
frontend/build/app/outputs/flutter-apk/app-debug.apk
```

### Sideload onto Personal Phone
1. Transfer `app-debug.apk` to your personal Android phone (via USB, Google Drive, or messaging).
2. Tap the `.apk` file on your phone and grant **Install from Unknown Sources**.
3. Open **Automatic Expense Tracker** on your phone!
4. Tap **Scan 30 Days** to auto-discover all bank accounts and credit cards from your SMS inbox and populates your 30-day expense history!

---

## 4. Milestone Verification Checklist

- [x] Backend: Vendor Category Rule engine (`RULE#<PayeeKey>`) and 1-tap rule learning implemented.
- [x] Backend: 30-Day Historical SMS & Email Backfill & Account Auto-Discovery engine implemented.
- [x] Backend: Credit Card Bills (`BILL#`), Peer Debt (`DEBT#`), Formal Loans (`LOAN#`), and Budget Alerts (`CAT#`) domain models implemented.
- [x] Terraform: DynamoDB single-table patterns and Budget Alert SNS topic configured and validated.
- [x] Flutter UI: `HistoricalBackfillCard`, `CategoryBreakdownView`, `UncategorizedReviewBanner`, `TransactionReviewModal`, and `BudgetScreen` widgets built.
- [x] Android: AndroidManifest.xml permissions (`READ_SMS`, `RECEIVE_SMS`, `INTERNET`) configured for personal phone sideloading.
- [x] Documentation: `docs/testing/ticket-30day-install-guide.md` created.
