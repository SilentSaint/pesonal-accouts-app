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
scripts/ci/verify-local-docker --no-build
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
available. Force pushes and branch deletion on `main` are prohibited. Every
change reaches `main` through a pull request; no direct commit or automation
write to `main` is permitted.

The repository owner controls the merge boundary, and only the repository owner
merges pull requests. A valid Codex review comment or qualifying PR-level
thumbs-up is a technical review outcome only; it never authorizes an agent to
merge. The watcher reports when all gates are satisfied and hands the PR to the
owner for the merge decision.

### Dark-factory review loop

Creating an issue-scoped PR is the trigger to start the review watcher. Before
the PR-creation task yields, arm a quiet Codex heartbeat automation in that
same task, bound to the PR URL/number and the exact current head SHA. On each
heartbeat, compare the live head with the tracked SHA; if it changed, invalidate
all prior review/approval signals, refresh the tracked SHA, and verify that a
review was triggered for the new head. After each fix commit, refresh the
tracked SHA and invalidate prior approvals. The heartbeat is the durable
watcher; a GitHub review request alone does not keep the Codex task alive. If
heartbeat automation is unavailable, keep the task active and wait for the
review response rather than reporting completion or handing off. The watcher
must:

1. On creation, verify that Codex review was triggered. If no review is pending
   or present, request `@codex review` once; do not create duplicate requests
   when GitHub already started the automatic review. For each request, record
   the request timestamp and head SHA; record the reviewed SHA when a response
   arrives.
2. Before implementing actionable review feedback, run the local `code-review`
   skill on the PR diff so its Standards and Spec agents review in parallel.
   Use those findings with the bot's feedback to scope the fix. If agents cannot
   be started, report the limitation and do not silently claim the local review
   step was completed.
3. For cycles 1 through 9, inspect every actionable request, implement the fixes
   on the PR branch, run focused validation, reply to the review, resolve the
   addressed conversations, and request another review.
4. Count one request-and-response sequence as one review cycle. Cycle 10 is the
   final automated response: if it contains actionable feedback, leave the PR
   unchanged, do not start cycle 11, and notify the owner with the cycle count
   and blocker. The owner decides whether to continue manually. A clean cycle 10
   may proceed to the merge gate. If the head changes after cycle 10, do not reset
   the cap or start another automated cycle: invalidate the prior approval, leave
   the PR unchanged, and hand it to the owner for a fresh manual decision.
5. For a review comment, verify the author is the configured Codex review bot,
   then classify the complete Codex review comment by meaning, not exact wording.
   It must explicitly state no major issues or an equivalent unambiguous
   approval. The existing “Keep it up!” verdict and equivalent forms such as
   “Nice work!”, “LGTM”, or “Looks good to me” are acceptable when they express
   that clear review verdict; praise alone is not. Actionable findings, requests
   for changes, caveats, conditional approval, or mixed feedback are not an
   approval. Ambiguous wording fails closed and is handed to the owner.
   Preserve the canonical example
   `Codex Review: Didn't find any major issues. Keep it up!`.
   Bind the approval to the reviewed head SHA: the SHA in the bot comment or a
   review record unambiguously associated with that comment must match the
   current PR head. A missing/ambiguous SHA, or any new commit after that
   review, invalidates the signal.

   A Codex `+1`/thumbs-up reaction can also be a technical approval signal only
   when it is on the PR itself and comes from the configured Codex review bot.
   Since the reaction carries no SHA, associate it with exactly one recorded
   review request: its reaction timestamp must be after the recorded request,
   and the current PR head must still match the tracked head. Multiple possible
   requests or any head change make the association ambiguous; fail closed and
   hand it to the owner. Reactions on review comments, reactions from the
   owner/other actors, and reactions whose reviewed head cannot be established
   do not satisfy this gate.
6. Report the PR ready for its owner only when a valid current-head Codex
   approval is present, no actionable review conversations remain unresolved,
   the PR is mergeable, the exact-head local Docker gate passes, and required
   checks are acceptable. Only the owner merges through the pull-request path;
   review approval is not merge authorization for an agent. Never write
   directly to `main`.
7. After merge, perform a read-only verification against the exact merged SHA.
   Never apply infrastructure automatically as a post-merge step.

The watcher stays quiet while the PR and review state are unchanged and reports
only meaningful review changes, completed fixes, cycle-limit stops, merge or
verification results, failures, or required owner action.

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
