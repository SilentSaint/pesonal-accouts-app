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

### Owner-approved AFK / stacked-PR policy (#110)

The current owner authorization is **PR-only**. Agents must not merge, deploy,
dispatch production workflows, or close issues. Implement one issue, finish
local public-seam verification, open a non-closing PR, and post the exact owner
production-observation checklist on the issue. Never use automatic-closing
keywords in PR descriptions.

Base the next implementation on the last opened PR's branch and target that
branch in its PR; record the predecessor PR and dependent code/issues in each
handoff. If the predecessor merged, fetch `main` and reconcile deliberately.
An open prerequisite can be implementation-ready only when its necessary code
is already present and verified in the preceding stack, not merely promised.
Runtime-only gates such as #94 remain owner-blocked without authorizing agent
deployment. This does not change any issue's acceptance or open state.

Keep one active implementation and a durable issue comment naming its branch,
PR, prerequisites and remaining work. Stop for genuinely missing prerequisites,
irreconcilable conflicts, missing credentials, or unsafe/destructive requirements.
The owner observes production and closes accepted issues; inconsistencies become
sub-issues. This policy supersedes waiting for every prerequisite's closure,
not production's merged-current-main requirement.

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

Create the first worktree and branch from `origin/main`, for example:

```bash
git fetch origin main
git worktree add -b codex/issue-123-description ../expense-issue-123 origin/main
git -C ../expense-issue-123 status --short
```

Agents must never share a mutable checkout. Under the approved stacked workflow,
use the predecessor branch as the explicit base for subsequent issues. Before
opening or updating a PR, fetch and compare against its declared base and current
`origin/main`; reconcile a merged predecessor without discarding its changes.
Rebase only in the isolated worktree and rerun candidate verification. Development
RED/GREEN runs may use uncommitted edits; release/PR claims must identify the
exact candidate commit, not conflate that with preliminary workspace evidence.

## Implementation and verification

Start with one failing test at the public seam described by the issue—such as a
use case, handler, repository port, or UI interaction. Make the smallest change
that makes it pass, then run the relevant suite. Final PR verification must run
against the exact candidate commit, not against an older checkout or a workspace
with extra files.

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

The owner-local hatch and the protected OIDC workflow call the same executable
`scripts/manual_production_deploy.sh`. Both require explicit owner approval and
the exact current `origin/main` SHA from a clean checkout. Local credentials
must be short-lived sessions for the configured least-privilege deployment role;
Actions uses OIDC and required reviewers on the `production` environment.
An Actions billing outage permits neither agent deployment nor a guard bypass.

The shared command runs all readiness gates on the candidate, binds saved-plan
and Lambda/web hashes to reviewed source and compiled endpoints, rejects unsafe
plans, and holds a conditional cross-host release lease alongside Terraform's
native state locks. Only the saved plan is applied. Exact live Lambda code hashes,
CloudFront version identity, and health must pass before recording `verified`.
Preparations and partial failures are recorded separately; no new alarms are a
requirement. The historically named `dev` stack in `ap-south-2` is preserved.

Do not deploy a PR/stack branch, dirty workspace, or arbitrary historical SHA.
Rollback uses a reviewed revert PR that restores known-good source on current
`main`, then the same guarded release command and owner observations. Preserve
the last owner-accepted manifest/SHA; do not overwrite it with a failed attempt.
See the [production runbook](../operations/production-readiness-runbook.md) for
exact inputs, private evidence, lease recovery, and the observation checklist.

## CI availability and baseline

Node Lambda tests and the Playwright runner are tracked in the reconciled
baseline. Release-contract tests are wired into `scripts/ci/verify` and CI.
PR CI runs for all target branches, including approved stacked bases. Missing
prerequisites still fail explicitly; never skip a failed gate to declare success.
While Actions is account-blocked, report that operational limitation and record
local candidate evidence honestly. Restore required checks only when the actual
clean-checkout jobs are running and green; do not claim unavailable CI passed.
