# Ticket 1 Full-Stack Verification & Testing Guide

## Core Financial Accounts & Transaction Ingestion (Backend, Flutter UI & Terraform)

This guide provides step-by-step instructions to set up, build, and verify the full-stack implementation of **Ticket 1** across all three layers: Backend Domain Logic, Terraform Infrastructure, and Flutter Frontend UI.

---

## 1. Backend Layer Verification (`/backend`)

Navigate to the backend directory:

```bash
cd backend
```

Execute the Java 21 Quarkus backend test suite:

```bash
./gradlew test
```

### Verified Seams & Test Suites

1. **`IngestTransactionUseCaseTest`**: Verifies manual transaction ingestion, account balance deduction, and SMS event parsing.
2. **`DynamoDbSingleTableRepositoryAdapterTest`**: Verifies Single-Table Partition Key (`PK = USER#<UserId>`) and Sort Key (`SK = ACC#<AccountId>`, `SK = TXN#<Timestamp>#<TxnId>`) mappings.

---

## 2. Infrastructure Layer Verification (`/terraform`)

Navigate to the terraform directory:

```bash
cd terraform
```

Validate the HCL syntax and plan execution for the `ExpenseTrackerData` DynamoDB table:

```bash
terraform fmt -check
terraform validate
```

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

Launch the responsive Glassmorphic dashboard app locally on Chrome or connected Android device:

```bash
flutter run -d chrome
```

---

## 4. Verification Checklists

- [x] Pure Domain entities (`FinancialAccount`, `Transaction`, `Money`) free of framework imports.
- [x] DynamoDB Single-Table schema defined in `/terraform/main.tf`.
- [x] Flutter responsive dashboard & `MethodChannel` SMS receiver stub in `/frontend`.
- [x] Backend tests passing in `./gradlew test`.
