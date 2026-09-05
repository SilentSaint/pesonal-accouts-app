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

`Production Deployment` is manual and targets the protected `production` environment.
It invokes the same reusable CI workflow first. The publish job cannot begin unless
every gate succeeds, then verifies the assumed AWS account before applying Terraform.
It builds a deployment marker containing the immutable Git SHA, waits for CloudFront
invalidation, and fetches that marker from CloudFront. It also verifies the unauthenticated
API health endpoint. A failed identity check, gate, invalidation, marker fetch, or smoke
check stops the deployment.

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
