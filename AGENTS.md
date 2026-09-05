# Project Rules & Guidance for AI Agents

## Mandatory repository workflow

Read and follow [the canonical engineering workflow](docs/engineering/workflow.md)
before making changes. It is the sole source for branch, worktree, PR, CI, merge,
and deployment guardrails; scoped instructions add only area-specific detail.

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

### 2A. Mandatory TDD Workflow for Every Behavioral Change
* **Use the `/tdd` skill** for every bug fix, feature, workflow change, or infrastructure change that can affect runtime behavior.
* **Red first at a public seam**: before changing production code, add or update a test against the public use-case, adapter, handler, or UI interaction that demonstrates the failure or specifies the behavior.
* **Green with the smallest change**: implement only enough code or configuration to pass that failing test, then refactor while the full relevant suite remains green.
* **One TDD issue is one vertical slice**: carry one behavior through all applicable layers—domain, application, persistence/infrastructure/IaC, and frontend—before calling the issue complete. A vertical slice may be backend-only when the behavior has no UI, but its public boundary and operational verification must still be covered.
* **Do not work horizontally**: do not batch-build models, repositories, APIs, tests, or screens as separate layers for multiple unfinished behaviors. Do not add speculative test scaffolding or close an issue for a partial layer.
* **Definition of done**: verify every issue acceptance criterion with automated tests and, where applicable, a live Playwright check and deployment check before closing the issue. Record any user-only verification that remains open.

### 3. Clean Code & Object-Oriented Design
* **SOLID Principles**: Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion.
* **Explicit Intent & Ubiquitous Language**: Name classes, methods, and variables using domain terminology defined in `CONTEXT.md`.
* **YAGNI & DRY**: Do not write speculative code or over-engineer abstractions before they are required by a failing test.

## Strict Issue Lifecycle & Definition of Done (DoD)

### Anti-Pattern Post-Mortem: Prevention of "Scaffolding vs. Implementation" Gap
During early milestones, an implementation gap occurred where GitHub issues were marked resolved and closed despite critical functionality remaining incomplete. Root cause analysis revealed:
1. **Confusing Domain POJO Scaffolding with Complete Vertical Slices**: Creating an isolated domain entity class (e.g., `LoanAccount.java` or `PeerDebtEntry.java`) or a static UI mockup was mistaken for completing the feature. The application use cases, repository ports, DynamoDB persistence adapters, business rules, and UI state wiring were missing.
2. **Premature Batch/Bulk Issue Closures**: Milestone commits introducing preliminary domain models were used to bulk-close multiple GitHub issues in a single action without individually verifying acceptance criteria.
3. **False Confidence from Narrow Test Suites**: Existing unit tests ran green, but zero tests existed for the newly closed feature domains, masking the complete lack of implementation.

### Mandatory Issue Resolution Protocol
To prevent this failure mode, **ALL AI AGENTS MUST ADHERE TO THE FOLLOWING RULES**:

1. **One Seam / One Vertical Slice per Issue**: Never bulk-close issues across multiple domain features in a single commit or batch operation. Work and close exactly one issue at a time.
2. **Full-Stack Hexagonal Definition of Done (DoD)**: An issue can **ONLY** be closed when ALL layers of the vertical slice are implemented and tested:
   * **Domain Layer**: Pure business entity/value object logic with unit tests.
   * **Application Layer**: Inbound use case interface (`XxxUseCase`) and application service (`XxxService`) with use-case test coverage.
   * **Persistence / Port Layer**: Outbound repository interface (`XxxRepository`) and concrete infrastructure adapter (e.g., DynamoDB single-table implementation with key partition scheme).
   * **Infrastructure / IaC**: Terraform resources (tables, topics, routes, Lambdas) provisioned and verified.
   * **Frontend UI**: Flutter screens/widgets actively connected to live state/repositories, handling loading, empty, and error states (no static mock-only data).
3. **Explicit Acceptance Criteria Verification**: Before closing any issue, the agent must systematically audit every checklist item in the GitHub issue description and run automated tests that assert the new behavior.
4. **No Scaffolding-Only Closures**: If only domain models or UI mockups are added as part of foundational work, the issue **MUST REMAIN OPEN** (or be split into sub-tasks) until the application and persistence seams are fully delivered.

### 4. Mandatory Browser End-to-End Testing with Playwright
* **Live Browser E2E Tests**: After completing every feature implementation, always perform end-to-end browser verification tests against the web app using Playwright to assert live UI rendering, user interactions, navigation flows, and API integrations.
* **Use Installed Chromium First**: Prefer a system Chrome/Chromium executable for `frontend/e2e_playwright_test.js`; the runner detects standard Linux paths, including `/snap/bin/chromium`.
* **Avoid Unnecessary Browser Downloads**: When Playwright is not installed, add only its pinned client with `cd frontend && npm install --no-save --no-package-lock playwright@1.47.2`. Do not run `npx playwright install chromium` while a compatible system browser is available; use a managed browser only when no Chrome/Chromium executable exists.

## Agent skills

### Issue tracker

GitHub Issues (`gh issue`) for `SilentSaint/pesonal-accouts-app`. See [issue-tracker.md](file:///home/rakshith/Antigravity/AutomaticExpenseTracker/docs/agents/issue-tracker.md).

### Domain docs

Single-context (`CONTEXT.md` + `docs/adr/`). See [domain.md](file:///home/rakshith/Antigravity/AutomaticExpenseTracker/docs/agents/domain.md).
