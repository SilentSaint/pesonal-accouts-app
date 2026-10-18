#!/usr/bin/env bash

set -euo pipefail

runbook="docs/operations/production-readiness-runbook.md"
manual_hatch="scripts/manual_production_deploy.sh"

grep -Fq 'required reviewers' "$runbook"
grep -Fq 'billing' "$runbook"
grep -Fq 'manual deployment hatch' "$runbook"
grep -Fq 'flock' "$manual_hatch"
grep -Fq 'set -euo pipefail' "$manual_hatch"
grep -Fq 'PRODUCTION_DEPLOY_APPROVED=YES' "$manual_hatch"
grep -Fq 'origin/main' "$manual_hatch"
grep -Fq 'scripts/ci/verify-local-docker' "$manual_hatch"
grep -Fq -- '--pull' "$manual_hatch"
grep -Fq 'AWS_ACCOUNT_ID' "$manual_hatch"
grep -Fq 'AWS_REGION' "$manual_hatch"
grep -Fq 'readonly EXPECTED_AWS_REGION="ap-south-2"' "$manual_hatch"
grep -Fq 'readonly EXPECTED_AWS_ACCOUNT_ID="727118420276"' "$manual_hatch"
grep -Fq 'readonly EXPECTED_TERRAFORM_ENVIRONMENT="dev"' "$manual_hatch"
grep -Fq 'readonly RELEASE_LOCK_FILE="/tmp/automatic_expense_tracker_production_release.lock"' "$manual_hatch"
grep -Fq 'Rollback release deliverables preserved' "$manual_hatch"
grep -Fq 'AET_GUARDED_RELEASE=YES' "$manual_hatch"

deploy_script="scripts/deploy_and_build.sh"
grep -Fq 'CANONICAL_ROOT_DIR=' "$deploy_script"
grep -Fq 'TERRAFORM_DIR="$CANONICAL_ROOT_DIR/terraform"' "$deploy_script"
grep -Fq 'EXPECTED_AWS_REGION' "$deploy_script"
grep -Fq 'readonly EXPECTED_AWS_REGION="ap-south-2"' "$deploy_script"
grep -Fq 'readonly EXPECTED_AWS_ACCOUNT_ID="727118420276"' "$deploy_script"
grep -Fq 'readonly EXPECTED_TERRAFORM_ENVIRONMENT="dev"' "$deploy_script"
grep -Fq 'set -euo pipefail' "$deploy_script"
grep -Fq 'terraform -chdir="$TERRAFORM_DIR" plan' "$deploy_script"
grep -Fq -- '-var="environment=$EXPECTED_TERRAFORM_ENVIRONMENT"' "$deploy_script"
grep -Fq 'terraform -chdir="$TERRAFORM_DIR" show -json' "$deploy_script"
grep -Fq 'planned_table_deletion_protection' "$deploy_script"
grep -Fq 'aws_dynamodb_table.expense_tracker_data' "$deploy_script"
grep -Fq 'deletion_protection_enabled' "$deploy_script"
grep -Fq 'Refusing deployment: production DynamoDB table ExpenseTrackerData must have deletion protection enabled in the reviewed plan' "$deploy_script"
grep -Fq 'contains(["dev", "prod", "production"], var.environment)' "terraform/main.tf"
grep -Fq 'aws_s3_bucket.web_bucket' "$deploy_script"
grep -Fq 'Refusing deployment: reviewed plan would destroy or replace existing production web bucket aws_s3_bucket.web_bucket.' "$deploy_script"
grep -Fq 'planned_values.outputs' "$deploy_script"
grep -Fq 'terraform -chdir="$TERRAFORM_DIR" apply' "$deploy_script"
grep -Fq -- '-auto-approve' "$deploy_script"
grep -Fq -- '-input=false' "$deploy_script"
grep -Fq 'deployment-version.json' "$deploy_script"
grep -Fq 'release-metadata.json' "$deploy_script"
grep -Fq 'last-verified-release.json' "$deploy_script"
grep -Fq -- '--exclude '\''last-verified-release.json'\''' "$deploy_script"
grep -Fq 'previous_commit' "$deploy_script"
grep -Fq 'aws cloudfront create-invalidation' "$deploy_script"
grep -Fq 'aws cloudfront wait invalidation-completed' "$deploy_script"
grep -Fq 'deployment-version.json?release=' "$deploy_script"
grep -Fq 'release-metadata.json?release=' "$deploy_script"
grep -Fq '/api/health' "$deploy_script"
grep -Fq 'last-verified-release.json' "$manual_hatch"
grep -Fq 'ROLLBACK_TARGET_SHA" == "PREVIOUS"' "$manual_hatch"
! grep -Fq 'if terraform apply' "$deploy_script"

plan_line="$(grep -nF 'terraform -chdir="$TERRAFORM_DIR" plan' "$deploy_script" | head -n1 | cut -d: -f1)"
show_line="$(grep -nF 'terraform -chdir="$TERRAFORM_DIR" show -json' "$deploy_script" | head -n1 | cut -d: -f1)"
deletion_protection_line="$(grep -nF 'planned_table_deletion_protection' "$deploy_script" | head -n1 | cut -d: -f1)"
bucket_protection_line="$(grep -nF 'planned_bucket_actions' "$deploy_script" | head -n1 | cut -d: -f1)"
web_build_line="$(grep -nF 'flutter build web' "$deploy_script" | head -n1 | cut -d: -f1)"
apply_line="$(grep -nF 'terraform -chdir="$TERRAFORM_DIR" apply' "$deploy_script" | head -n1 | cut -d: -f1)"
publish_line="$(grep -nF 'aws s3 sync' "$deploy_script" | head -n1 | cut -d: -f1)"

test -n "$plan_line"
test -n "$show_line"
test -n "$deletion_protection_line"
test -n "$bucket_protection_line"
test -n "$web_build_line"
test -n "$apply_line"
test -n "$publish_line"
test "$plan_line" -lt "$show_line"
test "$show_line" -lt "$deletion_protection_line"
test "$deletion_protection_line" -lt "$bucket_protection_line"
test "$bucket_protection_line" -lt "$web_build_line"
test "$web_build_line" -lt "$apply_line"
test "$apply_line" -lt "$publish_line"

lock_line="$(grep -nF 'flock' "$manual_hatch" | head -n1 | cut -d: -f1)"
local_gate_line="$(grep -nF 'scripts/ci/verify-local-docker' "$manual_hatch" | head -n1 | cut -d: -f1)"
aws_identity_line="$(grep -nF 'aws sts get-caller-identity' "$manual_hatch" | head -n1 | cut -d: -f1)"
deploy_line="$(grep -nF '"$SCRIPT_DIR/deploy_and_build.sh"' "$manual_hatch" | head -n1 | cut -d: -f1)"

test -n "$lock_line"
test -n "$local_gate_line"
test -n "$aws_identity_line"
test -n "$deploy_line"
test "$lock_line" -lt "$local_gate_line"
test "$local_gate_line" -lt "$aws_identity_line"
test "$local_gate_line" -lt "$deploy_line"

set +e
missing_approval_output="$(env -u PRODUCTION_DEPLOY_APPROVED bash "$manual_hatch" 2>&1)"
missing_approval_status=$?
set -e
test "$missing_approval_status" -ne 0
grep -Fq 'explicit owner approval' <<<"$missing_approval_output"

lock_file="/tmp/automatic_expense_tracker_production_release.lock"
set +e
concurrent_output="$(
  exec 200>"$lock_file"
  if flock -n 200; then
    PRODUCTION_DEPLOY_APPROVED=YES bash "$manual_hatch" 2>&1
  fi
)"
concurrent_status=$?
set -e
test "$concurrent_status" -ne 0
grep -Fq 'another production release is currently in progress' <<<"$concurrent_output"

grep -Fq 'ROLLBACK_TARGET_SHA' "$manual_hatch"
grep -Fq 'git merge-base --is-ancestor' "$manual_hatch"
grep -Fq 'ROLLBACK_TARGET_SHA' "$deploy_script"
grep -Fq 'git -C "$ROOT_DIR" merge-base --is-ancestor' "$deploy_script"

set +e
invalid_rollback_output="$(PRODUCTION_DEPLOY_APPROVED=YES ROLLBACK_TARGET_SHA=invalid-sha bash "$manual_hatch" 2>&1)"
invalid_rollback_status=$?
set -e
test "$invalid_rollback_status" -ne 0
grep -Fq 'invalid ROLLBACK_TARGET_SHA' <<<"$invalid_rollback_output"

set +e
unguarded_output="$(env -u AET_GUARDED_RELEASE bash "$deploy_script" 2>&1)"
unguarded_status=$?
set -e
test "$unguarded_status" -ne 0
grep -Fq 'use scripts/manual_production_deploy.sh' <<<"$unguarded_output"

echo "Production deployment guard policy is present."
