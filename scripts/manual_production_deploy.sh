#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ "${PRODUCTION_DEPLOY_APPROVED:-}" != "YES" ]]; then
  echo "Refusing production deployment: set PRODUCTION_DEPLOY_APPROVED=YES after explicit owner approval." >&2
  exit 1
fi

cd "$ROOT_DIR"

test "$(git branch --show-current)" = "main" || {
  echo "Refusing production deployment: checkout must be on main." >&2
  exit 1
}

git fetch --quiet origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || {
  echo "Refusing production deployment: local main must exactly match origin/main." >&2
  exit 1
}

test -z "$(git status --porcelain)" || {
  echo "Refusing production deployment: working tree must be clean." >&2
  exit 1
}

echo "Running the complete local Docker release gate before production deployment..."
"$ROOT_DIR/scripts/ci/verify-local-docker" --pull

test -z "$(git status --porcelain)" || {
  echo "Refusing production deployment: local validation changed the working tree." >&2
  exit 1
}

if [[ -z "${AWS_REGION:-}" ]]; then
  echo "Refusing production deployment: AWS_REGION is required." >&2
  exit 1
fi

if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
  echo "Refusing production deployment: AWS_ACCOUNT_ID is required." >&2
  exit 1
fi

export AWS_DEFAULT_REGION="$AWS_REGION"

actual_account="$(aws sts get-caller-identity --query Account --output text)" || {
  echo "Refusing production deployment: AWS credentials are unavailable or expired." >&2
  exit 1
}

if [[ "$actual_account" != "$AWS_ACCOUNT_ID" ]]; then
  echo "Refusing production deployment: expected AWS account $AWS_ACCOUNT_ID, got $actual_account." >&2
  exit 1
fi

export AET_GUARDED_RELEASE=YES

echo "All manual deployment guards passed for $(git rev-parse HEAD) in AWS account $AWS_ACCOUNT_ID."
exec "$SCRIPT_DIR/deploy_and_build.sh"
