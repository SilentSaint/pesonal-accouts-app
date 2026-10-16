# Production Readiness Runbook

## Required production configuration

### Canonical local release configuration

Production releases are executed locally using the guarded release hatch (`scripts/manual_production_deploy.sh`) with explicit owner authorization. The release environment requires the following operator configuration:

| Variable | Purpose |
| --- | --- |
| `AWS_REGION` | Target AWS region containing the production stack (e.g. `ap-south-2`); validated against pinned `EXPECTED_AWS_REGION`. |
| `AWS_ACCOUNT_ID` | Expected AWS account ID (e.g. `727118420276`); the release hatch validates STS identity and fails on any mismatch. |
| `PRODUCTION_DEPLOY_APPROVED=YES` | Explicit owner approval gate required to execute the release hatch. |

Operational authentication uses local AWS credentials (e.g. via `scripts/aws-dev-auth.sh` or the `agent-login` SSO profile). Deployments must not run with ambient unverified credentials.

After the first apply, confirm the email subscription sent for `budget-spending-alerts-prod` (or the configured environment) so operational alarms have an active human destination.

### Historical hosted configuration (superseded)

> [!NOTE]
> Hosted CI/CD workflows and GitHub Actions deployment pipelines are retired. The configuration below documents the historical hosted environment setup previously used before the canonical local release model was adopted.

In historical hosted automation, the GitHub `production` environment was protected with required reviewers and configured with these environment variables:

| Variable | Purpose |
| --- | --- |
| `AWS_REGION` | Region containing the production stack. |
| `AWS_ACCOUNT_ID` | Expected AWS account ID; workflows fail on any other identity. |
| `AWS_DEPLOY_ROLE_ARN` | OIDC-assumable, least-privilege deployment role. |
| `DYNAMODB_TABLE_NAME` | Production table name used by the restore-verification workflow. |

The historical deployment role was trusted only for this repository's `production` environment. It required scoped access to this stack's Terraform-managed resources, S3 web bucket, CloudFront distribution, and DynamoDB backup/restore operations. Long-lived AWS access keys were never configured in GitHub.

## Release gate and deployment

### Canonical local verification and release

The project follows a local-first engineering and release model (see `docs/operations/local-verification.md` and `docs/engineering/workflow.md`). Validation does not depend on hosted CI/CD (GitHub Actions or CodeBuild).

1. **Non-mutating verification gate**:
   Every change is validated locally before merging:
   ```bash
   scripts/ci/verify-local-docker --no-build
   ```
   This runs Java tests, Node.js/Lambda tests, local/release contracts, Terraform validation, Flutter analysis/tests, and Playwright browser E2E checks in an isolated Docker container with empty AWS credentials.

2. **Guarded production release hatch**:
   The owner-approved production release boundary is `scripts/manual_production_deploy.sh`. This manual deployment hatch requires explicit owner authorization (`PRODUCTION_DEPLOY_APPROVED=YES`), a clean checkout on `main` matching `origin/main`, executes `scripts/ci/verify-local-docker --pull`, asserts AWS account identity, and runs `scripts/deploy_and_build.sh`:
   ```bash
   export AWS_REGION=ap-south-2
   export AWS_ACCOUNT_ID='727118420276'
   PRODUCTION_DEPLOY_APPROVED=YES ./scripts/manual_production_deploy.sh
   ```

3. **Guarded rollback release hatch**:
   To roll back to an earlier known-good release commit, pass `ROLLBACK_TARGET_SHA` while staying on a clean checkout on `main`. The release driver on `main` verifies that the target commit is an ancestor contained in `origin/main`, provisions a detached worktree for the rollback target, runs validation against it, executes deployment, and preserves the rollback deliverables (mobile APK and web bundle) into the primary workspace `dev_builds/` before removing the temporary worktree:
   ```bash
   export AWS_REGION=ap-south-2
   export AWS_ACCOUNT_ID='727118420276'
   ROLLBACK_TARGET_SHA=<known-good-commit-sha> PRODUCTION_DEPLOY_APPROVED=YES ./scripts/manual_production_deploy.sh
   ```

### Historical and conditional hosted workflows

> [!NOTE]
> The hosted GitHub Actions workflows below represent historical context from earlier iterations and temporary manual deployment hatch procedures during a GitHub Actions billing outage. Hosted validation is retired and is not required for project delivery or production deployment.

Historically, `CI/CD & Operational Quality Gates` ran in hosted GitHub Actions:
1. Java tests, Flutter analysis/tests, and a release web build.
2. Playwright browser E2E against that release bundle.
3. Deterministic Node.js Lambda source/archive parity and Lambda archive tests.
4. A disposable DynamoDB Local table creation, transactional write, and read.
5. Terraform formatting and configuration validation.

Similarly, hosted `Production Deployment` was an Actions workflow dispatch hatch for the temporary GitHub Actions billing outage:
1. The workflow must be dispatched for `main`; another branch is rejected.
2. The dispatcher must select the explicit `yes` approval input.
3. The protected `production` environment must require your GitHub approval (with required reviewers).
4. Repository branch protection must require changes to arrive through a merged PR.
5. The reusable CI workflow must pass before the publish job can begin.

The billing incident context is preserved for historical audit; operational releases use the canonical guarded local hatch above.


Before running the release hatch, load the refreshable local AWS profile described in
`docs/operations/aws-development-auth.md` and confirm the identity with
`aws sts get-caller-identity`. Do not place credentials in the repository or export
short-lived access-key values into a shell profile.

The local release has these fail-closed stages:

1. The wrapper acquires the release lock (`/tmp/automatic_expense_tracker_production_release.lock` via `flock`)
   on the designated release host to prevent concurrent deployments across sessions or callers, requires explicit
   `PRODUCTION_DEPLOY_APPROVED=YES`, a clean working tree on `main` matching `origin/main`, and enforces that both
   `AWS_REGION` and `AWS_ACCOUNT_ID` strictly match pinned, readonly `EXPECTED_AWS_REGION` (`ap-south-2`) and
   `EXPECTED_AWS_ACCOUNT_ID` (`727118420276`, rejecting caller or ambient environment overrides). For standard
   releases, it deploys the clean `main` revision; for rollbacks (`ROLLBACK_TARGET_SHA`), the driver on `main` asserts
   that the target commit is an ancestor contained in `origin/main`, prepares an isolated temporary worktree to validate
   and deploy that target revision, and preserves generated deliverables before worktree cleanup.
2. `scripts/ci/verify-local-docker --pull` runs the complete D2 validation contract with
   production AWS credentials disabled. A failed gate stops before the AWS identity check
   or any AWS mutation; the working tree is checked again after validation, and `origin/main` currency is re-verified
   from the remote to prevent race conditions if `main` advanced during validation.
3. The wrapper compares `aws sts get-caller-identity` with `AWS_ACCOUNT_ID` and invokes the
   guarded deployment script only after the comparison succeeds.
4. The deployment script builds Lambda artifacts, creates a saved Terraform plan, and
   reads the planned endpoint and publication outputs before any AWS mutation. It then
   builds the web and Android artifacts using those planned endpoints. A failed artifact
   build stops before Terraform apply.
5. The script applies that exact saved plan, verifies that the applied Terraform outputs
   still equal the values used to build the artifacts, then publishes the web artifact.
   Terraform failure or output drift stops the sequence before publication.
6. CloudFront invalidation is awaited, and the deployed marker plus `${api_url}/api/health`
   are fetched with retries. A failed publication, invalidation, marker check, or health
   check exits non-zero.

Repository branch protection remains the control that ensures the `main` revision arrived
through a merged PR. The command requires the owner to set the approval variable
deliberately; do not export it in a shell profile.

For ordinary development validation, use the non-mutating gate instead:

```bash
scripts/ci/verify-local-docker --no-build
```

Retain the reviewed commit SHA, the complete local verifier log, the AWS account ID (not
credentials), Terraform output, CloudFront invalidation ID, deployment-marker response,
and API health response as release evidence. If a stage fails after Terraform has applied,
stop and inspect the Terraform plan and service state before retrying; this path does not
attempt an automatic rollback or publish financial records in logs.

Terraform state is stored in the encrypted, versioned S3 backend at
`automatic-expense-tracker-terraform-state-727118420276`, under
`production/terraform.tfstate`, with S3-native lockfiles enabled. Use Terraform 1.16.x
or newer for both local operations and CI. Never commit local state files or run an
apply with `-lock=false`.

## Backup and restore verification

The DynamoDB table has point-in-time recovery (PITR), encryption at rest, and production-only
deletion protection enabled in Terraform.

> [!NOTE]
> The scheduled GitHub Actions workflow `Verify DynamoDB Backup Restore` (`.github/workflows/verify-dynamodb-restore.yml`) has been retired alongside hosted CI/CD. The verification procedure below is preserved as historical context and operational guidance for manual AWS backup/restore tests:

Historical automated verification procedure:

1. Fails unless running in the expected AWS account and PITR is enabled.
2. Takes an isolated on-demand backup (`aws dynamodb create-backup`).
3. Restores it to a uniquely named verification table (`aws dynamodb restore-table-from-backup`).
4. Waits for `ACTIVE` and compares its key schema to the source table.
5. Deletes the verification table and temporary backup even after a failed check.

Operational restore testing must never scan or log financial records. Investigate any failure
before re-running it; do not delete the source production table or disable PITR.

## Alarm response

All alarms notify the operational SNS topic:

| Alarm | Initial response |
| --- | --- |
| `expense-tracker-ingestion-failures-*` | Review API Lambda errors and Gmail API failures; pause manual scans if errors persist. |
| `expense-tracker-authentication-failures-*` | Review API Gateway access logs for 401/403 spikes and validate the JWT issuer/audience configuration. |
| `expense-tracker-transaction-command-dlq-*` | Stop replay attempts, inspect the failed command, then remediate and replay only after preserving idempotency. |
| `expense-tracker-transaction-command-worker-throttles-*` | Check Lambda concurrency, SQS backlog, and downstream DynamoDB throttling. |
| `expense-tracker-reminder-delivery-failures-*` | Investigate the reminder delivery provider and affected recipients without exposing message contents in tickets. |

The repository currently has no reminder-delivery adapter or producer for the
`ExpenseTracker/Operational:ReminderDeliveryFailures` metric. The alarm is provisioned,
but it cannot observe real reminder failures until that adapter publishes a count of one
per failed delivery. This is a production-readiness dependency outside this infrastructure
slice; do not treat the alarm as active coverage until it is wired and exercised.
