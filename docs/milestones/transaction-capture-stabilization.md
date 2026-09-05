# Milestone: Stabilize Transaction Capture

Status: In progress; production baseline deployed
Scope: One complete path from transaction input to confirmed persisted transaction.

## Goal

An SMS or Gmail transaction can be reviewed, edited, confirmed, durably persisted, and displayed correctly after reload.

## Acceptance criteria

- [ ] SMS or Gmail input reaches the review UI.
- [ ] User edits to merchant, category, amount, and transfer linkage are preserved.
- [ ] Confirmation persists the transaction through the backend and DynamoDB adapter.
- [ ] A reload reads the confirmed transaction from the backend and renders it on the dashboard.
- [ ] Duplicate transactions are detected without creating an extra ledger entry.
- [ ] Failed commands expose a retry path and retry successfully.
- [ ] Sign-out clears local financial state and Gmail authorization state.
- [x] The latest verified frontend/backend revision is deployed to AWS production.
- [x] Backend tests pass: `cd backend && ./gradlew test`.
- [x] Flutter tests pass: `cd frontend && flutter test` (96 tests passed on 2026-09-01).
- [x] Playwright verifies the live production web shell: HTTP 200, expected title, and Flutter view loaded on 2026-09-01.

## Current verification baseline

- Repository cleanup and milestone changes are committed.
- The verified production deployment applied Terraform with no destroys, published the Flutter web bundle to S3, and completed CloudFront invalidation `I4INKQEAD7EUEXKEL27ZFBOSJA`.
- Backend suite passed on 2026-08-30; Flutter suite passed 96 tests on 2026-09-01.
- Flutter suite now passes 96 tests after correcting test authentication isolation, deterministic analytics time, entity-service authentication injection, and dashboard fixture/layout behavior.
- Playwright production smoke verification passed on 2026-09-01. This validates the live web shell; authenticated transaction-capture acceptance criteria remain open.
- Terraform state and deployment artifacts remain preserved.

## Rules for work in this milestone

- No new product areas or intelligence features.
- One issue or vertical slice at a time.
- Every change must identify the failing behavior, test seam, and user-visible result.
- Do not close the milestone until every acceptance criterion is verified.
