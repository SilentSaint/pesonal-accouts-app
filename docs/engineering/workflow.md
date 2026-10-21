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

The repository owner grants standing authorization for the agent to merge a PR
when a qualifying current-head Codex approval and every merge gate below pass.
That approval is the owner's delegated merge signal only under those
conditions; it is not a bypass for review, validation, mergeability,
required-check, branch-protection, or exact-head gates. Ambiguous or incomplete
evidence leaves the PR unmerged and is handed to the owner.

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
   or present, request `@codex review` once; do not create a duplicate while
   GitHub has already started an automatic review. If no trusted successful
   status establishes the current base (or a base-change invalidation is active),
   an automatic review without a prior base-bound request cannot authorize the
   initial status. Wait for that review to finish, then make one fresh,
   marker-backed request. For each explicit request, record its timestamp and
   full head SHA; record the reviewed SHA when a response arrives. Include this
   machine-readable marker in the top-level request comment before triggering
   each explicit review:
   `<!-- codex-review-request: head=<40-character-head-sha>; base=<40-character-base-sha>; cycle=<1-10> -->`.
   Use the GitHub API's comment creation timestamp as the request time; editing
   an older request must never make it fresh. Only a marker written by the
   repository owner is eligible. When multiple review requests are recorded for
   the same head and base (such as after an approval revocation and re-request),
   requests must have strictly ascending cycle numbers and creation timestamps;
   the latest valid request cycle supersedes earlier ones. Multiple request
   markers in a single comment, out-of-order cycles, or conflicting timestamps
   fail closed. Track the base branch SHA alongside the reviewed head SHA.
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
   the cap or start another automated cycle: invalidate the prior approval, persist
   the cycle-10 exhaustion failure onto the previous head to keep exhaustion latched
   even if reverted, leave the PR unchanged, and hand it to the owner for a fresh manual decision.
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
   review, invalidates the signal. Bind it to the reviewed base SHA as well:
   successful `codex-approval` statuses record the current PR base SHA. A base
   retarget or base-commit change writes a failure marker and requires a fresh
   Codex review; a thumbs-up additionally requires a review request recorded
   after that marker. The workflow reconciles PR edits immediately and its
   scheduled poll detects base-commit drift.

   A Codex `+1`/thumbs-up reaction can also be a technical approval signal only
   when it is on the PR itself and comes from the configured Codex review bot.
   Since the reaction carries no SHA, associate it with exactly one recorded
   review request: its reaction timestamp must be after the recorded request,
   and the current PR head must still match the tracked head. Multiple possible
   requests or any head change make the association ambiguous; fail closed and
   hand it to the owner. Reactions on review comments, reactions from the
   owner/other actors, and reactions whose reviewed head cannot be established
   do not satisfy this gate.
   A Codex comment or reaction by itself is evidence, not merge-time
   authorization; the active server-side `codex-approval` required status is
   the merge-time enforcement of the owner's delegated signal. Before merging,
   require an active server-side required status check or native approval,
   bound to the exact verified `expected_head_sha` and enforced for the
   authenticated merge identity through the merge operation.
   That gate must invalidate authorization when a new negative Codex response
   arrives or the qualifying signal is withdrawn; a final signal snapshot or a
   previously successful but no longer current check is insufficient. If the
   required head-bound authorization gate or its enforcement cannot be verified,
   leave the PR unmerged and hand it to the owner.
6. Merge only when a valid current-head Codex approval is present, all review
   conversations are resolved before merge, the PR is mergeable, the full local
   Docker gate passes on the exact current head without AWS credentials or
   production mutations, all required checks are acceptable, and any configured
   maintainer-approval requirement is satisfied. A missing,
   failing, or stale required check fails closed and requires fresh validation.
   Immediately before merging, re-fetch the PR and the current `main` ref. Record
   the verified current `expected_head_sha`, the PR `base_sha`, and the current
   `main` SHA; require the PR base to equal the current `main` SHA and verify the
   current `main` SHA is an ancestor of the PR head. A base equality check alone
   is insufficient. If the head, base, ancestry, or any gate evidence differs,
   invalidate the prior approval and gate results and require the branch to be
   updated/rebased and fresh review and validation.
   Before calling the merge operation, require an active strict server-side
   up-to-date branch-protection/ruleset gate enforced for the authenticated
   connector identity, with no administrator/custom-role/bypass-app exemption,
   a merge queue, or a repository-wide serialization lock that covers this final
   refresh through merge. A strict gate that the connector identity can bypass
   does not qualify; if enforcement for that identity cannot be verified, use the
   queue/serialization-lock path or leave the PR unmerged and hand it to the
   owner. The callable head guard alone does not serialize `main`. If no such
   active gate is present, leave the PR unmerged and hand it to the owner.
   Independently, require server-side conversation-resolution enforcement for
   the authenticated merge identity through the merge operation. The active
   ruleset/branch-protection rule must require all review conversations to be
   resolved, and the connector identity must not bypass it. This is intentionally
   stricter than the issue's actionable-thread minimum: GitHub's native
   enforcement treats threads uniformly, so all threads, including non-actionable
   ones, must be resolved. A final thread
   snapshot or a repository-wide serialization lock alone is insufficient; if
   enforcement is missing or unverifiable, leave the PR unmerged.
   Select the merge operation that matches the active serialization mechanism:
   for a strict branch-protection/ruleset gate or repository-wide serialization
   lock, invoke the GitHub connector's `github_merge_pull_request` operation with
   the verified `expected_head_sha`; for a merge queue, use a queue-capable
   asynchronous/enqueue operation with that verified head instead and never call
   the ordinary merge endpoint as a queue fallback. Treat an `enqueued` result as
   pending rather than as a merged SHA. Before queue completion, re-fetch the
   PR's current head and verify its Codex authorization remains valid and enforced
   for that exact PR head. Codex authorization remains bound to the exact current
   PR head through queue completion; a new PR commit invalidates that authorization
   even if its tree is identical. Also verify the current merge-group SHA and tree.
   Require the full local Docker gate and required checks on that exact merge-group
   SHA or a verified identical tree. The queue's server-side rules must block
   completion until both current PR-head authorization and merge-group validation
   and checks pass. A PR head change invalidates authorization; a merge-group SHA
   or tree change invalidates validation. Any state change must block completion
   until the authorization and validation are reevaluated for the new state. If the
   PR head, merge-group revision, or its gates cannot be verified,
   or queue policy cannot block completion until they pass, remove/cancel the
   entry when possible and leave the PR unmerged and hand it to the owner. Only
   after the queue reports the actual merge, perform step 7 against that eventual
   merged SHA. If the
   connector has no queue-capable operation, or enqueue fails, is cancelled,
   times out, or cannot be verified as merged, leave the PR unmerged and hand it
   to the owner.
   Never write directly to `main`, enable auto-merge as a shortcut, or
   deploy/mutate AWS. Any ambiguous or incomplete evidence leaves the PR
   unmerged and is handed to the owner.
7. After a direct merge operation or confirmed queue completion, verify the
   returned/eventual merged SHA and the resulting PR/ref state read-only against
   the exact expected result. Never apply infrastructure automatically as a
   post-merge step.

### Required Codex approval status bridge

`.github/workflows/codex-approval-status.yml` publishes the required
`codex-approval` commit status on the exact PR head SHA. It re-evaluates PR
comment/review events and the current GitHub API snapshot; the scheduled pass
also reconciles PR-level reactions. Scheduled and manual runs fan out across
open PRs, and each open PR is reconciled in its own per-PR concurrency group;
an event for one PR cannot cancel another PR's status revocation. A newer run
may replace an older run only for the same PR, then re-reads that PR's current
GitHub snapshot. Before emitting a reconciliation target, the selector records
deleted Codex feedback against the live PR head, so replacing or cancelling the
later matrix job cannot erase that revocation. Its GitHub Actions token is
limited to reading repository/PR metadata and writing commit statuses. All workflow
jobs check out trusted `main` policy code only; none checks out or executes PR
code. This status represents only
the Codex authorization signal, not the local Docker gate or other merge
requirements.

Deleting Codex-authored feedback, dismissing a qualifying Codex review, or receiving new negative Codex review activity
immediately publishes a failure status with a durable deleted-feedback revocation marker
or negative review failure on the live PR head, even if the PR
is closed or temporarily targets another base, before the reconcile job enters
its head-SHA concurrency queue. For all PR events, the workflow first resolves the live target PR head SHA before
entering the status-writing selector job; if the live head advances before selection executes, selection aborts to avoid writing failure under a stale head lock. Negative Codex review activity, review dismissals, and deletions share
the target PR head-SHA concurrency queue with `cancel-in-progress: true` to preempt any running
reconciliation for that commit, while general events do not share this selector queue so they
cannot displace a pending revocation while reconciliation cancels. This deleted-feedback revocation marker
persists across scheduled runs; the reconciler reads trusted status history, so an older
approval that remains visible in GitHub cannot restore authorization.
Only a current-head Codex approval or reaction recorded after that marker can
restore the status to success.

Commit statuses are scoped only by commit SHA and context, so authorization
requires the PR's current head SHA to be unique across open pull requests.
If multiple open pull requests share the same head commit, authorization fails
closed to prevent status cross-contamination. Trusted status markers record the
originating PR number (`pr=<number>; `) alongside the base SHA (`base-sha=<sha>; `).
Prior successes belonging to another PR are rejected in `priorApprovalBaseState`,
preventing a new pull request sharing a head commit from inheriting green status or
authorizing on unmarked reviews. Target selection flags inherited green status for
locked revocation when a new PR opens on a commit whose latest trusted success belongs to another
pull request. Duplicate-head failure writes are deferred to the head-locked `duplicate-head-status` job
with `queue: max` rather than written by the unlocked selector, ensuring all duplicate-head failure writes
and reconcile jobs are serialized under the target PR head commit SHA queue, while ordinary pull request events run in
isolated per-run selector groups so they do not enter the selector queue or displace pending
revocations. Before publishing a success status, the reconciler re-validates the live pull
request, base SHA, open pull request set, status history, and fresh review activity (comments,
reviews, and reactions) to prevent in-flight base changes, negative feedback, duplicate PR
heads, or deletion revocations from being overwritten. Revocation preemption is restricted strictly to
deletions, dismissals, and feedback classified as negative by `chatgpt-codex-connector[bot]`, matching the exact bot login rather than a
prefix, preventing other participants or delayed positive activity from displacing or cancelling a pending revocation. If the
live pull request head advances from the locked matrix head before reconciliation reads it, the
job aborts rather than writing statuses outside the acquired head lock. Fallback revocations
without an acquired head lock delegate to locked reconciliation rather than writing statuses
outside the lock. Once competing pull requests close or retarget such that the head SHA is unique
across open pull requests, reconciliation can clear the transient failure and publish success if
all other gates pass. The workflow triggers on PR edits across all target branches without a branch
filter, and reconciliation immediately revokes approval if a PR is retargeted away from `main`.

The approval evaluator requires a verified current base SHA. If trusted status
history does not establish a successful approval on that same base, or a
base-change invalidation is active, the evidence must follow a valid
request marker bound to the exact PR head and current base SHA. When multiple
valid request markers exist for the current head and base in strictly ascending
order, the latest valid request cycle is selected. Contradictory, ambiguous, or
out-of-order request markers fail closed. Cycle cap enforcement inspects all
owner-authored request markers across the PR before filtering to the current
head/base: any attempted cycle beyond 10, or attempt to reset the cap after
cycle 10 has been requested, fails closed immediately. Observing cycle 10 on
the current head latches a `cycle-10-exhausted` marker onto the commit's status
(including upon clean immediate approval) so subsequent deletion of the request cannot
reset the cap, while still allowing that final review cycle to complete on the matching head.
Over-limit request markers and historical cycle 10 markers are persisted to their historical heads
serialized under each head's concurrency lock, scoped with `pr=<number>`, and ignored by other
pull requests so reverting or force-pushing to that commit keeps exhaustion latched. Exhaustion
discovery inspects historical commits across the PR timeline, reviews, and comments beyond commits
reachable from the current head to prevent cap resets via force-push, and fails closed if
historical status or comment lookups fail. Target selection fails closed if comment history cannot be retrieved. A PR-level
thumbs-up always requires exactly one recorded request marker. An older or previous-base
request, an edited old review, or a response delivered after a marker but
originally submitted before it cannot qualify. When trusted history already
establishes the same base, a fresh unambiguous exact-head Codex review comment
can qualify without an additional request marker.

A Codex thumbs-down is also a revocation. Because GitHub does not emit reaction
removal events, the scheduled reconciler persists a
`negative-reaction-review-required` failure marker when it observes one. That
marker remains active if the reaction is later removed and can be cleared only
by a newer qualifying Codex approval or thumbs-up for the current head and
live base. A base change still requires a new base-bound request and review.
Compare a reaction with the review's immutable creation or submission time;
editing an older approval must not mask a later thumbs-down. Distinct review
responses are ordered by creation/submission time; editing an older approval
must not reorder it ahead of a later actionable review.

At merge time, the agent must also verify a completed successful run of this
workflow for the target PR after its latest Codex review activity, or a
successful scheduled run that reconciled that PR after the activity. A failed
target-selection/reconcile job, missing or unassociated workflow run, or run
that predates the latest relevant activity sets
`codexReconciliationSucceeded=false` and blocks the merge even if an older
`codex-approval` status remains green. Target selection can fail before the
current full head SHA is available, so that run cannot overwrite a prior commit
status; never infer current authorization from the old status alone.

Before relying on agent merges, the repository owner must configure an active
`main` ruleset requiring the `codex-approval` status from GitHub Actions, require
up-to-date branches and resolved review conversations, and ensure the
authenticated merge identity has no bypass exemption. The workflow must first
be merged to `main` before GitHub will run its comment/review triggers; this
initial policy installation therefore needs the owner's normal bootstrap merge.
Until the required status and its enforcement are verified, agents leave PRs
unmerged.

Before the policy script exists on trusted `main`, the selector succeeds with an
empty target list and skips reconciliation. This bootstrap no-op does not publish
`codex-approval` and does not satisfy `codexReconciliationSucceeded` or any
merge gate. Only a run that actually reconciles the target PR's current head
after its latest Codex review activity qualifies.

GitHub's standard Actions and webhook events do not include PR reaction
creation/removal. The bridge polls reactions every five minutes, so a removed
thumbs-up can remain reflected by a previously successful status until the next
poll. A green status by itself is therefore never enough: immediately before
merge, the agent must fetch the current PR-level reactions and verify that the
qualifying signal is still present on the exact current head. If that live
snapshot or the status is unavailable, stale, or ambiguous, leave the PR
unmerged. Do not enable GitHub auto-merge; the agent's final merge decision must
also pass every independent gate above.

The watcher stays quiet while the PR and review state are unchanged and reports
only meaningful review changes, completed fixes, cycle-limit stops, merge or
verification results, failures, or required owner action.

Close an issue only after the merged commit is deployed and production behavior
has been verified, or when the issue has no deployment impact and every listed
acceptance criterion has been verified. Record any remaining user-only check in
the issue rather than closing speculatively.

## Deployment contract

Production deployment is a separate, owner-approved operation. It may deploy
only a commit SHA contained in `main`, built from a clean checkout that exactly
matches `origin/main` (or a preserved known-good ancestor commit SHA contained
in `origin/main` during an owner-approved rollback). It must prevent concurrent
deployments (serializing the complete release operation from validation through
post-apply publication and verification via the release lock on the designated release host
using `/tmp/automatic_expense_tracker_production_release.lock`), use the guarded
local release hatch (`scripts/manual_production_deploy.sh`) with explicit owner
authorization (`PRODUCTION_DEPLOY_APPROVED=YES`), target the verified production
AWS account and pinned region (`ap-south-2` and `727118420276`, configured via `AWS_REGION` and
`AWS_ACCOUNT_ID` and validated against readonly `EXPECTED_AWS_REGION` and `EXPECTED_AWS_ACCOUNT_ID`,
rejecting caller or ambient environment overrides), execute the complete local Docker
verification gate before any AWS mutation, recheck `origin/main` currency after validation
to prevent stale-deployment races, build immutable artifacts before applying the saved
Terraform plan, verify post-apply output consistency, publish the web artifact and invalidate
CloudFront, execute live deployment marker (`deployment-version.json`), release metadata (`release-metadata.json`),
and health smoke checks, and upon successful verification publish the verified release marker
(`last-verified-release.json`) to durable S3 and local `dev_builds/` metadata, preserving the verified
known-good SHA for rollback. If live verification fails, the unverified release is never promoted, ensuring
failed deployments cannot overwrite the rollback pointer.

Do not deploy from a pull request or a dirty workspace. A rollback deploys a
preserved known-good commit SHA contained in `main` through the same guarded
release hatch using `ROLLBACK_TARGET_SHA=<known-good-sha>` or `ROLLBACK_TARGET_SHA=PREVIOUS`
(resolving the preserved known-good SHA from local or durable S3 release metadata `last-verified-release.json` /
`release-metadata.json`) from a clean checkout on `main` (the driver provisions an isolated worktree for the rollback target revision,
and preserves generated release deliverables to `dev_builds/` before worktree removal)
and records the resulting production verification.

## Current baseline dependency

Until repository-baseline reconciliation is complete, validation workflows
must report missing prerequisites honestly and must not be made required. In
the current remote baseline, `backend/lambda/test` and
`frontend/e2e_playwright_test.js` are absent, so their jobs fail with an explicit
reconciliation message. This does not prohibit the separate `codex-approval`
policy status; it is not a build/test result. Enable required validation checks
only after the reconciled `main` is clean and green.
