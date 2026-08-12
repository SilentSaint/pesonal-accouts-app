# Ticket 2 Full-Stack Verification & Testing Guide

## SMS & Email Ingestion & 15-Min Deduplication (Backend, Flutter UI & Terraform)

This guide details the step-by-step instructions to set up, build, and verify the implementation of **Ticket 2** across all three system layers: Backend Ingestion & Deduplication Domain Engine, Terraform Webhook Infrastructure, and Flutter Frontend Review UI.

---

## 1. Backend Layer Verification (`/backend`)

Navigate to the backend directory:

```bash
cd backend
```

Execute the Java 21 / Quarkus backend test suite:

```bash
./gradlew test
```

### Verified Seams & Test Suites

1. **`EmailTransactionParserTest`**: Verifies regex extraction of transaction amount, currency, account last 4 digits, merchant name, and timestamp from inbound email alerts.
2. **`DeduplicationEngineTest`**: Verifies candidate event evaluation within a ±15-minute window (900 seconds), auto-merging exact dual-channel matches, and flagging ambiguous matches with `NEEDS_REVIEW`.
3. **`IngestTransactionUseCaseTest`**: Verifies end-to-end SMS & Email ingestion, ±15m window deduplication, pending review listing, and 1-tap confirm/merge resolution.

---

## 2. Infrastructure Layer Verification (`/terraform`)

Navigate to the terraform directory:

```bash
cd terraform
```

Validate HCL formatting and syntax for SNS push webhook topics and EventBridge rules:

```bash
terraform fmt -check
terraform validate
```

### Infrastructure Resources Provisioned
- `aws_sns_topic.gmail_ingestion_webhook`: SNS topic for receiving real-time Gmail push notification webhooks.
- `aws_cloudwatch_event_rule.gmail_push_event_rule`: EventBridge rule filtering custom Gmail push notification events.
- `aws_cloudwatch_event_target.gmail_push_event_target`: Routing target directing Gmail events to the SNS topic.

---

## 3. Frontend UI Layer Verification (`/frontend`)

Navigate to the frontend directory:

```bash
cd frontend
```

Run Flutter static analysis and tests:

```bash
flutter analyze
flutter test
```

### Verified UI Components & Flows
1. **`UncategorizedReviewBanner`**: Displays a prominent glassmorphic warning banner when pending `NEEDS_REVIEW` or uncategorized transactions exist.
2. **`TransactionReviewModal`**: Interactive bottom sheet presenting pending transactions with 1-tap **Confirm Category** and **1-Tap Merge** actions.
3. **`review_banner_test.dart`**: Automated widget tests verifying review banner rendering and modal triggers.

---

## 4. Acceptance Criteria Checklist

- [x] Backend: Inbound SMS and Email event parsers and ±15m window deduplication engine implemented.
- [x] Backend: Ambiguous potential duplicate events flagged as `NEEDS_REVIEW`.
- [x] Terraform: SNS/EventBridge push webhook topic for real-time Gmail ingestion configured and validated.
- [x] Flutter UI: Uncategorized & duplicate transaction review banner with 1-tap confirm/merge modal created.
- [x] Documentation: `docs/testing/ticket-02-guide.md` created detailing backend tests, terraform validate, and Flutter UI review test steps.
