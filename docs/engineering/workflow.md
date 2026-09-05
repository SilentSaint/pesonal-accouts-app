# Engineering workflow

This is the repository's canonical workflow. GitHub `main` is the source of truth.
No person, agent, API, or automation may create a direct commit on `main`.

## Delivery lifecycle

```text
issue
→ isolated worktree and issue branch from origin/main
→ RED test at a public seam
→ minimal vertical implementation
→ local verification
→ pull request
→ clean-checkout CI
→ review and required checks
→ merge
→ deploy the merged commit SHA
→ production verification
→ close issue
```

One issue is one thin vertical slice. A branch may not bundle unrelated work.
Scaffolding, an isolated domain model, a mock screen, or a narrow passing test does
not complete an issue: the acceptance criteria must be verified through every
applicable layer.

## Agent opening sequence

Every agent starts in this order:

```text
read workflow
→ fetch origin/main
→ inspect assigned issue
→ create isolated worktree
→ confirm clean starting state
→ run RED-GREEN-REFACTOR
→ run verification
→ open PR
→ wait for clean-checkout CI
```

Create the worktree and branch from `origin/main`, for example:

```bash
git fetch origin main
git worktree add -b codex/issue-123-description ../expense-issue-123 origin/main
git -C ../expense-issue-123 status --short
```

Agents must never share a mutable checkout. Before opening or updating a PR,
fetch and compare the branch with `origin/main`. If it is behind, rebase only in
the isolated worktree and re-run the candidate's verification. Do not use an
uncommitted workspace as an input to a deployment, a test claim, or a PR.

## Implementation and verification

Start with one failing test at the public seam described by the issue—such as a
use case, handler, repository port, or UI interaction. Make the smallest change
that makes it pass, then run the relevant suite. Tests must run against the exact
candidate commit, not against an older checkout or a workspace with extra files.

Run the smallest relevant script during development. Before opening a PR, run:

```bash
scripts/ci/verify
```

The scripts are intentionally fail-closed: a missing runtime, test suite, or
Playwright runner is reported as a failure. They do not clean the checkout,
rewrite source, alter history, or deploy.

Generated output is never source. Do not commit build directories, Gradle or
Flutter caches, dependency folders, archives, Terraform state, or deployment
artifacts. A generated file needed to operate production must be reconstructed
from tracked source in a clean checkout.

## Pull requests and merge

Open a pull request referencing exactly one issue. The PR must state the
user-observable behavior, public test seam, RED evidence, tests run, deployment
impact, rollback approach, and any user-only verification. Clean-checkout CI
must validate the candidate SHA shown in the workflow log.

Reviewers require all configured checks, resolved conversations, and a branch
current with `main` before merge. Use serialized merges or a merge queue when
available. Force pushes and branch deletion on `main` are prohibited. The
repository owner retains an explicitly documented emergency bypass only.

Close an issue only after the merged commit is deployed and production behavior
has been verified, or when the issue has no deployment impact and every listed
acceptance criterion has been verified. Record any remaining user-only check in
the issue rather than closing speculatively.

## Deployment contract

Production deployment is a separate, protected workflow. It may deploy only a
SHA contained in `main`, built from a clean checkout. It must use GitHub Actions
OIDC for AWS rather than persistent credentials, target a protected production
environment, prevent concurrent deployments, record the deployed SHA, execute
post-deployment smoke checks, and preserve a known-good SHA for rollback.

Do not deploy from a pull request or a dirty workspace. A rollback deploys a
known-good commit SHA through the same protected workflow and records the
resulting production verification.

## Current baseline dependency

Until repository-baseline reconciliation is complete, workflows must report
missing prerequisites honestly and must not be made required. In the current
remote baseline, `backend/lambda/test` and `frontend/e2e_playwright_test.js` are
absent, so their jobs fail with an explicit reconciliation message. Enable
required checks only after the reconciled `main` is clean and green.
