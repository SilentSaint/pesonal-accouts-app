# Production readiness and release runbook

## Authority and one release command

The #110 AFK policy is **PR-only**: agents do not merge, deploy, dispatch production
workflows, or close issues. The owner deploys, observes, and accepts the result.
Stacked PRs may target their predecessor branches; production may not. Every release
must use the current, reviewed, merged `origin/main` SHA.

Both the owner-local manual deployment hatch and protected GitHub OIDC deployment
invoke `scripts/manual_production_deploy.sh`. That executable delegates to
`scripts/deploy_and_build.sh`; invoking the delegate does not bypass any guard.
GitHub Actions billing/account restrictions do not grant deployment approval.
While Actions is unavailable, the owner can explicitly authorize the same local
command after reviewing the merged candidate and infrastructure changes.

This is an update command for the **existing production-used stack named `dev` in
`ap-south-2`**, not a bootstrap or migration command. Do not rename it to `prod`,
recreate resources, disable locking, or add CloudWatch alarms as release cleanup.

## Prerequisites and deployment identity

Use a separate clean checkout on `main`, exactly matching freshly fetched
`origin/main`. Untracked source, staged changes, a stale SHA, local detached HEAD,
or source changes during preparation fail closed. Installed dependencies and
generated output are ignored, not accepted as reviewed source. Never use the
owner's dirty development checkout.

Required tools: Bash, Git, Node.js 20+, npm, Python 3, Java/JDK 21, the tracked
Gradle wrapper, Flutter (CI uses stable 3.24.x), Terraform 1.16.x, AWS CLI v2,
curl, and Linux `sha256sum`. Keep the existing Android SDK/Java environment valid
for `flutter build apk`; the command does not overwrite a personal SDK path.
The ARM64 **debug APK** remains a required, archived owner-testing deliverable,
not a signed Play Store release. APK failures block infrastructure publication.
Physical-device acceptance remains an owner task.

Use a system Chrome/Chromium executable, including `/snap/bin/chromium`, or set
`E2E_BROWSER_EXECUTABLE` explicitly. Browser readiness uses the existing runner.
It installs only `playwright@1.47.2` with `--no-save --no-package-lock` if the
client is missing; it never downloads a browser. Missing tools, SDKs, dependencies,
or browser failures are errors, not permission to skip readiness.
Actions runs `scripts/run-browser-e2e.sh --prepare` before invoking the release;
this prepares prerequisites only and does not replace the actual browser gate.

If provider installation exhausts a quota-limited `/tmp`, set
`TF_PLUGIN_CACHE_DIR` to an existing, private disk-backed directory dedicated to
this checkout and rerun the gate. This avoids extracting the large provider into
`/tmp` without changing browser profile paths. An excessively long `TMPDIR` can
break Terraform provider Unix-socket handshakes; Snap Chromium can also refuse
profiles under `/var/tmp`. Do not change global caches or wipe shared directories.

| Input | Requirement |
| --- | --- |
| `PRODUCTION_DEPLOY_APPROVED` | `YES`, deliberately set for one owner-approved invocation, never a shell-profile default. |
| `AWS_ACCOUNT_ID` | Expected 12-digit account, confirmed independently by the owner. |
| `AWS_DEPLOY_ROLE_ARN` | Exact IAM deployment role in that account. Current STS identity must be its assumed-role session, not an IAM user or another role. |
| `AWS_REGION` | `ap-south-2`; `AWS_DEFAULT_REGION`, if present, must agree. |
| `AWS_PROFILE` | Optional local SSO/assume-role profile supplying short-lived credentials for the configured role. |

Example **for the owner only**, after obtaining the approved short-lived assumed
role session:

```bash
AWS_REGION=ap-south-2 \
AWS_ACCOUNT_ID='<expected-account-id>' \
AWS_DEPLOY_ROLE_ARN='arn:aws:iam::<expected-account-id>:role/<deployment-role>' \
PRODUCTION_DEPLOY_APPROVED=YES \
./scripts/manual_production_deploy.sh
```

Do not use long-lived access keys in GitHub. When Actions is available, protect the
`production` environment with **required reviewers**, configure the three AWS
variables there, and restrict the role's OIDC trust to this repository's
`production` environment. The workflow accepts only `main` plus explicit `yes`
approval and requires the reusable readiness job. Its detached checkout must
match `GITHUB_SHA`, `refs/heads/main`, and current `origin/main`. It sets up tools
and calls the same command, which runs readiness again on the actual candidate.

The role must have least-privilege access to only this existing Terraform stack:
its Lambda deployments and configuration reads, API resources, necessary scoped
IAM changes/PassRole, web bucket publication, CloudFront invalidation, and
encrypted state/lock objects. Restrict the extra release-lease permissions to
`dynamodb:PutItem`, `GetItem`, and `DeleteItem` on `ExpenseTrackerData`, with
`dynamodb:LeadingKeys` restricted to `RELEASE#production` for these operations.
No financial records are scanned. The release command does not require backup
or restore permissions; separately authorize restore rehearsals. The owner must
inspect the role's actual trust and attached policies: checking its ARN alone
does not prove that an administrator configured least privilege.

Account, role, and configured region are revalidated before apply and publication.
Use ordinary AWS endpoints, not local emulators or custom endpoint overrides, for
an owner production release. External cloud tools in release contract tests are
isolated fakes and need no real credentials.

## Gates, saved plan, and publication

`scripts/ci/verify` runs generated-artifact checks, public release-command
regressions, Java tests, Flutter tests and analysis, Terraform validation, Lambda
source/archive tests, release web build, and Playwright. Informational analyzer
findings remain visible but nonfatal (`--no-fatal-infos`), matching CI; warnings
and errors remain fatal. Node tests and the Playwright runner are now tracked.
CI additionally exercises the existing disposable DynamoDB Local gate. PR CI
covers stacked PR bases as well as `main`.

The release sequence is:

1. Enforce owner approval, clean current-main provenance, expected assumed-role
   identity, and region; acquire the shared cross-host release lease.
2. Initialize the existing locked remote backend; require all five current API,
   WebSocket, web bucket, distribution ID, and CloudFront URL outputs.
3. Run every readiness gate. Build the web client with those actual endpoints
   and exercise that exact final bundle in Playwright. Snapshot and compare
   checked Node/Java/web hashes; never rebuild a Lambda archive after its checks.
   Build the debug APK and archive the candidate.
4. Save `terraform plan` to a private file with native state locking. Parse
   `terraform show -json` privately and print only resource actions and changed
   field names, not state/configuration values. Compare all planned deployment
   targets with the build inputs; changed, missing, or unknown targets stop the
   release. Every planned Lambda must reference one of the checked archives
   with its exact hash. Region/environment must remain `ap-south-2`/`dev`.
5. Reject destruction, replacement, forgetting resources, incomplete/unsupported
   plans, and creation of new CloudWatch alarms. The command has **no bypass**
   for these. A needed migration requires a separate reviewed owner decision and
   implementation, not an ad hoc `terraform apply`. Review the merged IaC diff
   before approval; the generated plan is then reviewed against this constrained
   policy. The redacted summary and private full plan/log permit inspection.
6. Recheck source, identity, lease ownership, artifacts and plan integrity. Apply
   **only the saved plan**, never a newly computed unplanned apply. On success,
   require each deployed Lambda's AWS `CodeSha256` to match the candidate and
   its state/update status to be ready. A healthy old API is not code-parity proof.
7. Recheck the candidate, publish only archived `web/`, wait for CloudFront
   invalidation, compare the exact live version marker, and require API health.
   Only then relinquish the lease conditionally and record `verified`.

An init/plan/apply, validator, upload, invalidation, Lambda identity, version or
health failure exits nonzero, stops later publication stages and cannot print
success. S3 synchronization is **not atomic**: a failed upload may leave mixed
objects. The marker is a necessary identity check, not a transaction across AWS
services or proof of financial-feature acceptance.

State stays in the existing encrypted, versioned S3 backend
`automatic-expense-tracker-terraform-state-727118420276`, key
`production/terraform.tfstate`, with `use_lockfile = true`. State access and KMS
permissions must remain restricted. The command uses a fresh private Terraform
data directory and the `default` workspace, rejects `TF_CLI_ARGS*` overrides,
and uses a finite lock wait. Never use `-lock=false`, force-unlock a live owner,
commit state, log raw state, or upload a plan/state JSON to web or GitHub artifacts.

## Cross-host lease and owner recovery

GitHub concurrency alone cannot serialize local workstations with Actions.
Both use one conditional item in existing `ExpenseTrackerData`:
`PK=RELEASE#production`, `SK=LEASE`. Acquisition uses
`attribute_not_exists(PK)`; consistent reads check ownership before mutation;
release deletes only when its unique `owner` token still matches. This is
release metadata, outside `USER#` financial partitions. No new infrastructure
is provisioned. It protects **participating release commands across hosts**,
not privileged ad hoc AWS commands.

There is deliberately **no TTL, auto-expiry, automatic stealing, or failure-time
delete**. A paused process must not resume after another release has taken over.
Failures after lease acquisition retain ownership, including preparation failures.
A lost acquire response may also leave an item: inspect rather than retrying blind.
A killed process can leave `preparing`/`prepared` evidence and a held lease; that
is an interrupted release, never a verified one.

Before clearing a failed lease, the owner must stop and prove termination of
the original process/workflow on its host, establish the actual Lambda/S3/state
outcome, and preserve the evidence. Terraform's separate native state lock must
also be respected. Read only the lease key, not financial data:

```bash
aws dynamodb get-item --region ap-south-2 --table-name ExpenseTrackerData \
  --key '{"PK":{"S":"RELEASE#production"},"SK":{"S":"LEASE"}}' \
  --consistent-read
```

After that investigation, with the same authorized assumed role, delete **only
the observed token** using the conditional lease helper:

```bash
node scripts/release_lease.js release '<observed-owner-token>'
```

A mismatched token must fail. Never remove the condition or add expiry as
recovery. A new guarded invocation creates new evidence and a fresh saved plan;
it does not resume a partially applied or stale plan.

## Evidence, partial failures, and rollback

Each invocation gets a unique private
`dev_builds/releases/<sha>-<suffix>/` directory under `umask 077`. Keep it on
owner-controlled durable storage with restricted access:

| Evidence | Meaning |
| --- | --- |
| `source.tar`, `source.json` | Tracked source archive, commit/tree identity, source hash, and lease owner. |
| `provenance.json` | Source, expected account/role, region/environment, and compiled API/WebSocket targets; no credentials. |
| `node.zip`, `java.zip`, `app-debug.apk`, `web/`, `manifest.json` | Candidate bytes and SHA-256 identities; the web digest excludes its self-referential marker. |
| `terraform.plan`, `terraform-plan.json`, `terraform-*.log` | **Sensitive private** saved plan and diagnostics, never publication inputs. |
| `plan-review.json` | Non-sensitive plan hash, actions/changed field names, stable deployment targets and expected Lambda code hashes. |
| `verified-lambdas.json` | Actual post-apply code identities/readiness. |
| `events.jsonl`, `status.json` | Phase history and `preparing`, `prepared`, `failed`, or `verified` outcome. |

`prepared` proves readiness, not deployment. Only `verified` records completion
of the live code/version/health checks; it still does not close the issue or
replace owner acceptance. A failure records its last phase and exit code.
Terraform values stay out of shared logs. Do not attach private plans, state,
credentials, financial records, or full diagnostic logs to public issues.

Actions retains only the explicit non-sensitive evidence allowlist for 90 days,
not raw plans, state, source archives or binaries. Runner-local private diagnostics
are ephemeral; when further private plan inspection is needed, the owner should
use the same guarded path from a controlled local checkout. Preserve accepted
release identities separately before artifact retention expires.

Maintain the last **owner-accepted, verified** SHA/release ID and corresponding
manifest; do not overwrite that record on preparation or failed deployment.
There is no cross-service atomic rollback. After a partial failure, inspect
Terraform state and the recorded stage before attempting a new release.

Rollback is a **revert PR** restoring known-good source on top of current `main`.
For example, create an isolated issue branch, use `git revert <bad-commit>` (or
`git revert -m 1 <bad-merge>` for a merge), resolve/review changes, run readiness,
and open a non-closing PR. After owner merge, deploy the resulting current-main
SHA through `scripts/manual_production_deploy.sh` or the protected OIDC workflow.
Record the new release identity and rerun observations. Do not check out an old
SHA and bypass the current-main guard, replay a stale saved plan, copy old ZIPs
directly to Lambda, or sync an old web directory directly to S3. Destructive
schema/data reversals require a separate owner-reviewed recovery plan.

## Owner observation checklist for #59

Keep #59 open until the owner completes and records these observations:

1. Confirm the merged SHA is the intended current `main`, role trust/permissions
   and account/region are correct, state encryption/versioning/native locking
   remain enabled, and no plan proposes resource deletion/replacement/new alarms.
2. Observe one explicitly approved guarded release. Retain its release ID,
   manifest, plan hash, provenance, final `verified` status and all Lambda
   code-hash comparisons. Record any interrupted/failed attempt separately.
3. Fetch CloudFront `deployment-version.json` and compare the exact candidate
   manifest; confirm invalidation completed and `/api/health` succeeds.
   Use the browser to load/reload the deployed app on desktop/mobile, navigate
   existing screens, and observe API/WebSocket traffic targets without logging
   tokens or financial content. The local browser smoke is not this live check.
4. Confirm an overlapping invocation is rejected while ownership is held, and
   successful completion releases only its own lease. Exercise real failure
   recovery only in an explicitly approved safe operational window; the isolated
   public-command tests already inject failures without production mutation.
5. Preserve a known-good release record and review the revert-PR rollback path.
   Install/check the debug APK on a physical device if accepting that deliverable.
   Report inconsistencies as sub-issues; the owner decides acceptance and closure.

## Backup/restore and existing operational resources

PITR and encryption are declared for the data table; deletion protection currently
depends on `environment == "prod"` and must **not** be claimed enabled merely
because this `dev` stack serves production. Inspect actual settings without
renaming the environment. The existing backup/restore workflow uses an isolated
verification table and never scans financial data. Final live restore rehearsal
and cross-feature acceptance belong to #122, not this initial release repair.

Do not add CloudWatch alarms as a release requirement or remove existing resources.
Existing alarm/SNS declarations are unchanged; their presence is not proof of
working producers or human notification coverage. In particular, the declared
reminder-failure metric has no delivery adapter/producer in this baseline.
Use existing redacted operational diagnostics and explicit failure status for
this release. User-facing bill/budget/risk notifications are separate features.
