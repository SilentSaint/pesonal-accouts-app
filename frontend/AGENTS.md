# Frontend Engineering Guidelines (Flutter / Dart)

Read and follow the repository [engineering workflow](../docs/engineering/workflow.md)
first. This file adds frontend-specific constraints only.

## Architecture (Clean Architecture / Hexagonal for Flutter)

```text
lib/
├── domain/                    # Pure Dart domain entities, value objects, and business rules
├── application/               # State management (BLoC/Notifier), use cases, and app controllers
├── infrastructure/            # Adapters: Platform channel (Android SMS listener), Local DB (Isar/SQLite), API Client
└── presentation/              # Responsive UI screens, widgets, themes, and design tokens
```

## Frontend Coding & TDD Best Practices

### 1. Pure Dart Domain Layer
* Entities in `domain/` must be pure Dart classes without Flutter UI widgets or HTTP package imports.

### 2. Seam Isolation & Platform Channels
* Native Android SMS listening is encapsulated behind a clean domain interface (`SmsIngestionPort`).
* The UI interacts exclusively with application state controllers / use cases, never directly with platform channels or HTTP clients.

### 3. Frontend TDD Rules
* Unit test domain logic and application state controllers test-first using `package:test`.
* Widget tests verify user interaction at the presentation boundary without reaching into low-level network or native platform channels.
* Invoke the `/tdd` skill for every frontend bug fix, feature, auth change, or API integration change.
* Write the failing test first at the public UI/application seam, make the smallest change to reach green, then refactor with the relevant Flutter suite passing.
* Each issue must be one vertical slice from user interaction through application state and its live adapter/API. Do not build horizontal batches of widgets, services, or models for unfinished behaviors.
* Do not close an issue for static UI scaffolding or isolated widget tests; verify loading, empty, error, retry, and live behavior required by the issue.
