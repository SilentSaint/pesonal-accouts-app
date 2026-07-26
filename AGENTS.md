# Project Rules & Guidance for AI Agents

## Core Architectural & Engineering Principles

### 1. Domain-Driven Design (DDD) & Hexagonal Architecture
* **Pure Domain Core**: All core business logic, domain entities, value objects, and domain events live in the pure domain layer, completely free of framework imports (no AWS, Quarkus, Flutter, or database dependencies).
* **Ports & Adapters (Hexagonal)**:
  * **Inbound Ports (Primary/Driver)**: Define interfaces for application use cases.
  * **Outbound Ports (Secondary/Driven)**: Define interfaces for persistence, messaging, and external services.
  * **Adapters**: Implement ports (e.g. DynamoDB repository adapters, REST API adapters, Android SMS receiver adapters).
* **Dependency Inversion**: Dependencies point strictly **inward** toward the Domain Core. High-level domain policy must never depend on low-level technical infrastructure details.

### 2. Test-Driven Development (TDD) Protocol
* **Red → Green → Refactor**: Write a failing test first that specifies expected behavior, write the minimal code to pass it, and keep tests passing.
* **Test at Public Seams**: Write tests against public interfaces and use case boundaries. Never test private methods or mock internal implementation details.
* **No Tautological Assertions**: Assertion expected values must be derived from known domain specifications, independent of the implementation under test.
* **Vertical Slicing**: Implement features in thin vertical slices (one use case / seam at a time). Never write bulk speculative tests upfront.

### 3. Clean Code & Object-Oriented Design
* **SOLID Principles**: Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion.
* **Explicit Intent & Ubiquitous Language**: Name classes, methods, and variables using domain terminology defined in `CONTEXT.md`.
* **YAGNI & DRY**: Do not write speculative code or over-engineer abstractions before they are required by a failing test.
