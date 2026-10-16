#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ "${PRODUCTION_DEPLOY_APPROVED:-}" != "YES" ]]; then
  echo "Refusing production deployment: set PRODUCTION_DEPLOY_APPROVED=YES after explicit owner approval." >&2
  exit 1
fi

cd "$ROOT_DIR"

readonly RELEASE_LOCK_FILE="/tmp/automatic_expense_tracker_production_release.lock"
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
fi

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

test -z "$(git status --porcelain)" || {
  echo "Refusing production deployment: working tree must be clean." >&2
  exit 1
}

DEPLOY_TARGET_DIR="$ROOT_DIR"
DEPLOY_TARGET_REV="$(git rev-parse HEAD)"

if [[ -n "${ROLLBACK_TARGET_SHA:-}" ]]; then
  if ! git merge-base --is-ancestor "$target_rev" origin/main; then
    echo "Refusing rollback deployment: commit $target_rev is not contained in origin/main." >&2
    exit 1
  fi
  DEPLOY_TARGET_REV="$target_rev"
  DEPLOY_TARGET_DIR="$(mktemp -d /tmp/aet-rollback-worktree.XXXXXX)"
  git worktree add --quiet --detach "$DEPLOY_TARGET_DIR" "$DEPLOY_TARGET_REV"
  cleanup_rollback_worktree() {
    if [[ -n "${DEPLOY_TARGET_DIR:-}" && -d "$DEPLOY_TARGET_DIR" ]]; then
      git worktree remove --force "$DEPLOY_TARGET_DIR" 2>/dev/null || rm -rf "$DEPLOY_TARGET_DIR"
    fi
  }
  trap cleanup_rollback_worktree EXIT
  export ROLLBACK_TARGET_SHA="$DEPLOY_TARGET_REV"
fi

echo "Running the complete local Docker release gate before production deployment..."
if [[ "$DEPLOY_TARGET_DIR" != "$ROOT_DIR" ]]; then
  "$ROOT_DIR/scripts/ci/verify-local-docker" --rollback-worktree "$DEPLOY_TARGET_DIR" --pull
else
  "$ROOT_DIR/scripts/ci/verify-local-docker" --pull
fi

if [[ -n "${ROLLBACK_TARGET_SHA:-}" ]]; then
  test -z "$(git -C "$DEPLOY_TARGET_DIR" status --porcelain)" || {
    echo "Refusing rollback deployment: local validation changed the target working tree." >&2
    exit 1
  }
fi

test -z "$(git status --porcelain)" || {
  echo "Refusing production deployment: local validation changed the working tree." >&2
  exit 1
}

git fetch --quiet origin main || {
  echo "Refusing production deployment: failed to refresh origin/main from remote after validation." >&2
  exit 1
}

test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || {
  echo "Refusing production deployment: origin/main advanced during verification (local HEAD is $(git rev-parse HEAD), remote is $(git rev-parse origin/main))." >&2
  exit 1
}

if [[ -n "${ROLLBACK_TARGET_SHA:-}" ]]; then
  if ! git merge-base --is-ancestor "$ROLLBACK_TARGET_SHA" origin/main; then
    echo "Refusing rollback deployment: commit $ROLLBACK_TARGET_SHA is no longer contained in origin/main." >&2
    exit 1
  fi
fi

readonly EXPECTED_AWS_REGION="ap-south-2"

if [[ -z "${AWS_REGION:-}" ]]; then
  echo "Refusing production deployment: AWS_REGION is required." >&2
  exit 1
fi

if [[ "$AWS_REGION" != "$EXPECTED_AWS_REGION" ]]; then
  echo "Refusing production deployment: AWS_REGION must be $EXPECTED_AWS_REGION, got '$AWS_REGION'." >&2
  exit 1
fi

readonly EXPECTED_AWS_ACCOUNT_ID="727118420276"

if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
  echo "Refusing production deployment: AWS_ACCOUNT_ID is required." >&2
  exit 1
fi

if [[ "$AWS_ACCOUNT_ID" != "$EXPECTED_AWS_ACCOUNT_ID" ]]; then
  echo "Refusing production deployment: AWS_ACCOUNT_ID must be $EXPECTED_AWS_ACCOUNT_ID, got '$AWS_ACCOUNT_ID'." >&2
  exit 1
fi

export AWS_DEFAULT_REGION="$AWS_REGION"

actual_account="$(aws sts get-caller-identity --query Account --output text)" || {
  echo "Refusing production deployment: AWS credentials are unavailable or expired." >&2
  exit 1
}

if [[ "$actual_account" != "$EXPECTED_AWS_ACCOUNT_ID" ]]; then
  echo "Refusing production deployment: expected AWS account $EXPECTED_AWS_ACCOUNT_ID, got $actual_account." >&2
  exit 1
fi

export AET_GUARDED_RELEASE=YES

echo "All manual deployment guards passed for $DEPLOY_TARGET_REV in AWS account $EXPECTED_AWS_ACCOUNT_ID."
deploy_status=0
TARGET_DIR="$DEPLOY_TARGET_DIR" "$SCRIPT_DIR/deploy_and_build.sh" || deploy_status=$?

if [[ "$deploy_status" -eq 0 && "$DEPLOY_TARGET_DIR" != "$ROOT_DIR" ]]; then
  if [[ -d "$DEPLOY_TARGET_DIR/dev_builds" ]]; then
    mkdir -p "$ROOT_DIR/dev_builds"
    for item in "$DEPLOY_TARGET_DIR/dev_builds"/*; do
      if [[ -e "$item" ]]; then
        basename_item="$(basename "$item")"
        rm -rf "$ROOT_DIR/dev_builds/$basename_item"
        cp -r "$item" "$ROOT_DIR/dev_builds/$basename_item"
      fi
    done
    echo "Rollback release deliverables preserved at $ROOT_DIR/dev_builds."
  fi
fi

exit "$deploy_status"
