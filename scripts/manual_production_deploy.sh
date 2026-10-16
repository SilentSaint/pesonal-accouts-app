#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ "${PRODUCTION_DEPLOY_APPROVED:-}" != "YES" ]]; then
  echo "Refusing production deployment: set PRODUCTION_DEPLOY_APPROVED=YES after explicit owner approval." >&2
  exit 1
fi

cd "$ROOT_DIR"

RELEASE_LOCK_FILE="${TMPDIR:-/tmp}/automatic_expense_tracker_release.lock"
exec 200>"$RELEASE_LOCK_FILE"
if ! flock -n 200; then
  echo "Refusing production deployment: another production release is currently in progress." >&2
  exit 1
fi

if [[ -n "${ROLLBACK_TARGET_SHA:-}" ]]; then
  target_rev="$(git rev-parse --verify "${ROLLBACK_TARGET_SHA}^{commit}" 2>/dev/null)" || {
    echo "Refusing rollback deployment: invalid ROLLBACK_TARGET_SHA '$ROLLBACK_TARGET_SHA'." >&2
    exit 1
  }
  git fetch --quiet origin main || {
    echo "Refusing rollback deployment: failed to refresh origin/main from remote." >&2
    exit 1
  }
  if ! git merge-base --is-ancestor "$target_rev" origin/main; then
    echo "Refusing rollback deployment: commit $target_rev is not contained in origin/main." >&2
    exit 1
  fi
  local_rev="$(git rev-parse HEAD)"
  if [[ "$local_rev" != "$target_rev" ]]; then
    echo "Refusing rollback deployment: local HEAD ($local_rev) does not match ROLLBACK_TARGET_SHA ($target_rev)." >&2
    exit 1
  fi
  export ROLLBACK_TARGET_SHA="$target_rev"
else
  test "$(git branch --show-current)" = "main" || {
    echo "Refusing production deployment: checkout must be on main." >&2
    exit 1
  }

  git fetch --quiet origin main || {
    echo "Refusing production deployment: failed to refresh origin/main from remote." >&2
    exit 1
  }
  test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || {
    echo "Refusing production deployment: local main must exactly match origin/main." >&2
    exit 1
  }
fi

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
