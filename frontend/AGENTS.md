# Frontend Engineering Guidelines (Flutter / Dart)

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
