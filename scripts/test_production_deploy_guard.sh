#!/usr/bin/env bash

set -euo pipefail

workflow=".github/workflows/production-deploy.yml"
runbook="docs/operations/production-readiness-runbook.md"
manual_hatch="scripts/manual_production_deploy.sh"

grep -Fq 'confirm_production_deploy:' "$workflow"
grep -Fq "github.ref == 'refs/heads/main'" "$workflow"
grep -Fq 'environment:' "$workflow"
grep -Fq 'required reviewers' "$runbook"
grep -Fq 'billing' "$runbook"
grep -Fq 'manual deployment hatch' "$runbook"
grep -Fq 'PRODUCTION_DEPLOY_APPROVED=YES' "$manual_hatch"
grep -Fq 'origin/main' "$manual_hatch"
grep -Fq 'flutter test' "$manual_hatch"

echo "Production deployment guard policy is present."
