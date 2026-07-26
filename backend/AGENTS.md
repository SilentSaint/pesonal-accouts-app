# Backend Engineering Guidelines (Java 21 / Quarkus / AWS)

## Package Architecture (Hexagonal DDD)

```text
com.automaticexpense.tracker.backend/
├── domain/                    # Pure Java domain models, entities, value objects, domain rules
├── application/               # Inbound ports (use cases) & outbound ports (repository interfaces)
└── infrastructure/            # Adapters (DynamoDB repository, API Gateway handlers, SNS webhooks)
```

## Backend Coding & TDD Best Practices

### 1. Pure Java Domain Core
* Domain models inside `domain/` must be pure Java 21 with zero Quarkus, AWS SDK, or Jackson annotations.
* Domain logic is validated via fast JUnit 5 unit tests with 0ms startup time.

### 2. Hexagonal Ports & Adapters
* Application use cases implement Inbound Ports (`com.automaticexpense.tracker.backend.application.port.in`).
* Persistence adapters implement Outbound Ports (`com.automaticexpense.tracker.backend.application.port.out`).
* Infrastructure code (DynamoDB, AWS Lambda request handlers) translates external requests/records to pure domain models before calling use cases.

### 3. Backend TDD Rules
* Write unit tests for domain entities and use-case ports using JUnit 5 and AssertJ.
* Use stub/fake implementations for outbound ports in application layer tests rather than heavy mocking frameworks wherever possible.
