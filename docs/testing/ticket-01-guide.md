# Ticket 1 Verification & Testing Guide

## Core Financial Account & Transaction Ingestion Foundation

This guide provides step-by-step instructions to set up, build, and verify the implementation of **Ticket 1** (Core Financial Account & Transaction Ingestion Foundation).

---

## 1. Environment & Prerequisites

- **Java JDK**: Version 21 (OpenJDK 21)
- **Gradle Wrapper**: `./gradlew` provided in `/backend`

---

## 2. Setup & Build Instructions

Navigate to the backend project directory:

```bash
cd backend
```

Build the pure domain and application module:

```bash
./gradlew build
```

---

## 3. Running Test Verification

Execute all test suites for the domain core, application use cases, and DynamoDB single-table adapters:

```bash
./gradlew test
```

### Verified Test Cases

1. **`IngestTransactionUseCaseTest`**
   - Verifies manual transaction ingestion and automatic account balance adjustment (`currentBalance = currentBalance - amount`).
   - Verifies SMS transaction ingestion and automatic matching by `lastFourDigits`.

2. **`DynamoDbSingleTableRepositoryAdapterTest`**
   - Verifies single-table Partition Key (`PK = USER#<UserId>`) and Sort Key formatting (`SK = ACC#<AccountId>` and `SK = TXN#<Timestamp>#<TxnId>`).
   - Verifies serialization and deserialization of `FinancialAccount` and `Transaction` entities.

3. **`SmsTransactionParserTest`**
   - Verifies regex extraction of monetary amounts, account identifiers, and merchant names from raw bank SMS bodies.

---

## 4. Manual Verification via Executable Test Runner

You can also run a targeted single-class test verification:

```bash
./gradlew test --tests "com.automaticexpense.tracker.application.IngestTransactionUseCaseTest"
```

Expected Output:
```text
BUILD SUCCESSFUL in 1s
```
