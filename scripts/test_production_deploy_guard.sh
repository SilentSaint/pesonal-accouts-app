#!/usr/bin/env bash

set -euo pipefail

runbook="docs/operations/production-readiness-runbook.md"
manual_hatch="scripts/manual_production_deploy.sh"

grep -Fq 'required reviewers' "$runbook"
grep -Fq 'billing' "$runbook"
grep -Fq 'manual deployment hatch' "$runbook"
grep -Fq 'set -euo pipefail' "$manual_hatch"
grep -Fq 'PRODUCTION_DEPLOY_APPROVED=YES' "$manual_hatch"
grep -Fq 'origin/main' "$manual_hatch"
grep -Fq 'scripts/ci/verify-local-docker' "$manual_hatch"
grep -Fq -- '--pull' "$manual_hatch"
grep -Fq 'AWS_ACCOUNT_ID' "$manual_hatch"
grep -Fq 'AWS_REGION' "$manual_hatch"
grep -Fq 'AET_GUARDED_RELEASE=YES' "$manual_hatch"

deploy_script="scripts/deploy_and_build.sh"
grep -Fq 'set -euo pipefail' "$deploy_script"
grep -Fq 'terraform -chdir="$TERRAFORM_DIR" apply' "$deploy_script"
grep -Fq -- '-auto-approve' "$deploy_script"
grep -Fq -- '-input=false' "$deploy_script"
grep -Fq 'deployment-version.json' "$deploy_script"
grep -Fq 'aws cloudfront create-invalidation' "$deploy_script"
grep -Fq 'aws cloudfront wait invalidation-completed' "$deploy_script"
grep -Fq 'deployment-version.json?release=' "$deploy_script"
grep -Fq '/api/health' "$deploy_script"
! grep -Fq 'if terraform apply' "$deploy_script"

local_gate_line="$(grep -nF 'scripts/ci/verify-local-docker' "$manual_hatch" | head -n1 | cut -d: -f1)"
aws_identity_line="$(grep -nF 'aws sts get-caller-identity' "$manual_hatch" | head -n1 | cut -d: -f1)"
deploy_line="$(grep -nF 'exec "$SCRIPT_DIR/deploy_and_build.sh"' "$manual_hatch" | head -n1 | cut -d: -f1)"

test -n "$local_gate_line"
test -n "$aws_identity_line"
test -n "$deploy_line"
test "$local_gate_line" -lt "$aws_identity_line"
test "$local_gate_line" -lt "$deploy_line"

set +e
missing_approval_output="$(env -u PRODUCTION_DEPLOY_APPROVED bash "$manual_hatch" 2>&1)"
missing_approval_status=$?
set -e
test "$missing_approval_status" -ne 0
grep -Fq 'explicit owner approval' <<<"$missing_approval_output"

set +e
unguarded_output="$(env -u AET_GUARDED_RELEASE bash "$deploy_script" 2>&1)"
unguarded_status=$?
set -e
test "$unguarded_status" -ne 0
grep -Fq 'use scripts/manual_production_deploy.sh' <<<"$unguarded_output"

echo "Production deployment guard policy is present."
