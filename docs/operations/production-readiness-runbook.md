# Production Readiness Runbook

## Required production configuration

Protect the GitHub `production` environment with required reviewers and configure these
environment variables:

| Variable | Purpose |
| --- | --- |
| `AWS_REGION` | Region containing the production stack. |
| `AWS_ACCOUNT_ID` | Expected AWS account ID; workflows fail on any other identity. |
| `AWS_DEPLOY_ROLE_ARN` | OIDC-assumable, least-privilege deployment role. |
| `DYNAMODB_TABLE_NAME` | Production table name used by the restore-verification workflow. |

The deployment role must be trusted only for this repository's `production` environment.
It needs scoped access to this stack's Terraform-managed resources, S3 web bucket,
CloudFront distribution, and DynamoDB backup/restore operations. Do not configure
long-lived AWS access keys in GitHub.

After the first apply, confirm the email subscription sent for
`budget-spending-alerts-prod` (or the configured environment) so operational alarms
have an active human destination.

## Release gate and deployment

`CI/CD & Operational Quality Gates` runs on every pull request and main-branch push:

1. Java tests, Flutter analysis/tests, and a release web build.
2. Playwright browser E2E against that release bundle.
3. Deterministic Node.js Lambda source/archive parity and Lambda archive tests.
4. A disposable DynamoDB Local table creation, transactional write, and read.
5. Terraform formatting and configuration validation.

`Production Deployment` is the manual deployment hatch for the temporary GitHub Actions
billing outage. It is deliberately narrow:

1. The workflow must be dispatched for `main`; another branch is rejected.
2. The dispatcher must select the explicit `yes` approval input.
3. The protected `production` environment must require your GitHub approval.
4. Repository branch protection must require changes to arrive through a merged PR.
5. The reusable CI workflow must pass before the publish job can begin.

This means the hatch deploys only the reviewed contents of `main`, and does not provide
a branch-based or local-workstation production bypass. If GitHub Actions is unavailable
because of account billing restrictions, this hatch cannot run until Actions is restored;
use the local validation commands in the repository runbook, but do not treat them as
production deployment approval.

After approval, the publish job verifies the assumed AWS account before applying Terraform.
It builds a deployment marker containing the immutable Git SHA, waits for CloudFront
invalidation, and fetches that marker from CloudFront. It also verifies the unauthenticated
API health endpoint. A failed identity check, gate, invalidation, marker fetch, or smoke
check stops the deployment.

The billing problem is an operational dependency, not a reason to weaken the release
boundary. Record any GitHub Actions billing/account incident in the deployment notes and
re-check Actions availability before relying on this hatch.

When GitHub Actions is unavailable, the owner-approved local fallback is:

```bash
PRODUCTION_DEPLOY_APPROVED=YES ./scripts/manual_production_deploy.sh
```

The wrapper refuses to proceed unless the checkout is on `main`, exactly matches
`origin/main`, has no uncommitted changes, passes the local backend and Flutter gates,
and has valid AWS credentials. Repository branch protection remains the control that
ensures the `main` revision arrived through a merged PR. The command requires the owner
to set the approval variable deliberately; do not export it in a shell profile.

Terraform state is stored in the encrypted, versioned S3 backend at
`automatic-expense-tracker-terraform-state-727118420276`, under
`production/terraform.tfstate`, with S3-native lockfiles enabled. Use Terraform 1.16.x
or newer for both local operations and CI. Never commit local state files or run an
apply with `-lock=false`.

## Backup and restore verification

The DynamoDB table has point-in-time recovery, encryption at rest, and production-only
deletion protection enabled. `Verify DynamoDB Backup Restore` runs monthly at 03:00 UTC
on the first day of the month and can be manually dispatched for a protected, audited
verification.

The workflow:

1. Fails unless it is running in the expected AWS account and PITR is enabled.
2. Takes an isolated on-demand backup.
3. Restores it to a uniquely named verification table.
4. Waits for `ACTIVE` and compares its key schema to the source table.
5. Deletes the verification table and temporary backup even after a failed check.

The workflow never scans or logs financial records. Investigate any failure before
re-running it; do not delete the source table or disable PITR as remediation.

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
