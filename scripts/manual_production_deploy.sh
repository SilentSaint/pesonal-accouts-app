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

readonly EXPECTED_AWS_REGION="ap-south-2"
readonly EXPECTED_AWS_ACCOUNT_ID="727118420276"
readonly EXPECTED_TERRAFORM_ENVIRONMENT="production"

if [[ -n "${ROLLBACK_TARGET_SHA:-}" ]]; then
  if [[ "$ROLLBACK_TARGET_SHA" == "PREVIOUS" ]]; then
    resolved_sha=""
    bucket="$(terraform -chdir="$ROOT_DIR/terraform" output -raw s3_web_bucket_name 2>/dev/null || true)"
    if [[ -z "$bucket" || "$bucket" == "unknown-output" ]]; then
      state_bucket="automatic-expense-tracker-terraform-state-$EXPECTED_AWS_ACCOUNT_ID"
      state_key="production/terraform.tfstate"
      state_err_file="$(mktemp /tmp/aet-s3-state-err.XXXXXX)"
      state_status=0
      state_json="$(aws s3 cp "s3://$state_bucket/$state_key" - 2>"$state_err_file")" || state_status=$?
      state_err="$(cat "$state_err_file" 2>/dev/null || true)"
      rm -f "$state_err_file"
      if [[ "$state_status" -eq 0 ]]; then
        bucket="$(jq -er '.outputs.s3_web_bucket_name.value // empty' <<<"$state_json" 2>/dev/null || true)"
      else
        if grep -Eqi '(NoSuchBucket|bucket.*does not exist)' <<<"$state_err" || ! grep -Eqi '(404|NoSuchKey|Key .* does not exist|specified key does not exist)' <<<"$state_err"; then
          echo "Refusing rollback deployment: failed to read remote terraform state from s3://$state_bucket/$state_key." >&2
          echo "$state_err" >&2
          exit 1
        fi
      fi
    fi
    if [[ -z "$bucket" || "$bucket" == "unknown-output" || "$bucket" == "None" ]]; then
      list_err_file="$(mktemp /tmp/aet-s3-list-err.XXXXXX)"
      list_status=0
      list_output="$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'expense-tracker-web-${EXPECTED_TERRAFORM_ENVIRONMENT}-')].Name" --output text 2>"$list_err_file")" || list_status=$?
      list_err="$(cat "$list_err_file" 2>/dev/null || true)"
      rm -f "$list_err_file"
      if [[ "$list_status" -ne 0 ]]; then
        echo "Refusing rollback deployment: failed to list S3 buckets for discovery." >&2
        echo "$list_err" >&2
        exit 1
      fi
      bucket_list=()
      if [[ "$list_output" =~ ^\[.*\]$ ]]; then
        mapfile -t bucket_list < <(jq -r '.[]' <<<"$list_output" 2>/dev/null || true)
      elif [[ -n "$list_output" && "$list_output" != "None" ]]; then
        IFS=$' \t\n' read -ra bucket_list <<<"$list_output"
      fi
      if [[ "${#bucket_list[@]}" -gt 1 ]]; then
        echo "Refusing rollback deployment: ambiguous production web bucket discovery; found multiple matching buckets: ${bucket_list[*]}." >&2
        exit 1
      elif [[ "${#bucket_list[@]}" -eq 1 ]]; then
        bucket="${bucket_list[0]}"
      else
        bucket=""
      fi
    fi
    if [[ -z "$bucket" || "$bucket" == "unknown-output" || "$bucket" == "None" ]]; then
      echo "Refusing rollback deployment: could not discover web bucket from terraform output, remote state, or S3." >&2
      exit 1
    fi

    # Query durable production metadata first
    s3_verified_err_file="$(mktemp /tmp/aet-s3-verified-err.XXXXXX)"
    s3_verified_status=0
    s3_verified="$(aws s3 cp "s3://$bucket/last-verified-release.json" - 2>"$s3_verified_err_file")" || s3_verified_status=$?
    s3_verified_err="$(cat "$s3_verified_err_file" 2>/dev/null || true)"
    rm -f "$s3_verified_err_file"

    if [[ "$s3_verified_status" -ne 0 ]]; then
      if grep -Eqi '(NoSuchBucket|bucket.*does not exist)' <<<"$s3_verified_err" || ! grep -Eqi '(404|NoSuchKey|does not exist)' <<<"$s3_verified_err"; then
        echo "Refusing rollback deployment: failed to read verified release metadata from s3://$bucket/last-verified-release.json." >&2
        echo "$s3_verified_err" >&2
        exit 1
      fi
      s3_verified=""
    else
      verified_commit="$(jq -er '.commit // empty' <<<"$s3_verified" 2>/dev/null || true)"
      verified_prev="$(jq -er '.previous_commit // empty' <<<"$s3_verified" 2>/dev/null || true)"
      if [[ ! "$verified_commit" =~ ^[0-9a-zA-Z._-]{7,64}$ ]]; then
        echo "Refusing rollback deployment: verified release marker in s3://$bucket/last-verified-release.json is malformed or missing a valid commit SHA." >&2
        echo "Raw marker content: $s3_verified" >&2
        exit 1
      fi
      if ! git rev-parse --verify "${verified_commit}^{commit}" >/dev/null 2>&1; then
        echo "Refusing rollback deployment: verified release marker in s3://$bucket/last-verified-release.json references invalid commit '$verified_commit'." >&2
        exit 1
      fi
      if [[ -n "$verified_prev" ]]; then
        if [[ ! "$verified_prev" =~ ^[0-9a-zA-Z._-]{7,64}$ ]]; then
          echo "Refusing rollback deployment: verified release marker in s3://$bucket/last-verified-release.json contains malformed previous_commit." >&2
          echo "Raw marker content: $s3_verified" >&2
          exit 1
        fi
        if ! git rev-parse --verify "${verified_prev}^{commit}" >/dev/null 2>&1; then
          echo "Refusing rollback deployment: verified release marker in s3://$bucket/last-verified-release.json references invalid previous_commit '$verified_prev'." >&2
          exit 1
        fi
      fi
    fi

    s3_live_source=""
    s3_live_err_file="$(mktemp /tmp/aet-s3-live-err.XXXXXX)"
    s3_live_status=0
    s3_live="$(aws s3 cp "s3://$bucket/deployment-version.json" - 2>"$s3_live_err_file")" || s3_live_status=$?
    s3_live_err="$(cat "$s3_live_err_file" 2>/dev/null || true)"
    rm -f "$s3_live_err_file"

    if [[ "$s3_live_status" -eq 0 ]]; then
      s3_live_source="s3://$bucket/deployment-version.json"
    else
      if grep -Eqi '(NoSuchBucket|bucket.*does not exist)' <<<"$s3_live_err" || ! grep -Eqi '(404|NoSuchKey|does not exist)' <<<"$s3_live_err"; then
        echo "Refusing rollback deployment: failed to read live release metadata from s3://$bucket/deployment-version.json." >&2
        echo "$s3_live_err" >&2
        exit 1
      fi
      s3_live=""
      # Also check release-metadata.json in S3 as secondary fallback
      s3_meta_err_file="$(mktemp /tmp/aet-s3-meta-err.XXXXXX)"
      s3_meta_status=0
      s3_live="$(aws s3 cp "s3://$bucket/release-metadata.json" - 2>"$s3_meta_err_file")" || s3_meta_status=$?
      s3_meta_err="$(cat "$s3_meta_err_file" 2>/dev/null || true)"
      rm -f "$s3_meta_err_file"
      if [[ "$s3_meta_status" -eq 0 ]]; then
        s3_live_source="s3://$bucket/release-metadata.json"
      else
        if grep -Eqi '(NoSuchBucket|bucket.*does not exist)' <<<"$s3_meta_err" || ! grep -Eqi '(404|NoSuchKey|does not exist)' <<<"$s3_meta_err"; then
          echo "Refusing rollback deployment: failed to read release metadata from s3://$bucket/release-metadata.json." >&2
          echo "$s3_meta_err" >&2
          exit 1
        fi
        s3_live=""
      fi
    fi

    # Fall back to local release metadata only if durable S3 metadata is confirmed absent
    if [[ -z "$s3_verified" && -z "$s3_live" ]]; then
      if [[ -f "$ROOT_DIR/dev_builds/last-verified-release.json" ]]; then
        s3_verified="$(cat "$ROOT_DIR/dev_builds/last-verified-release.json" 2>/dev/null || true)"
        if [[ -n "$s3_verified" ]]; then
          verified_commit="$(jq -er '.commit // empty' <<<"$s3_verified" 2>/dev/null || true)"
          verified_prev="$(jq -er '.previous_commit // empty' <<<"$s3_verified" 2>/dev/null || true)"
          if [[ ! "$verified_commit" =~ ^[0-9a-zA-Z._-]{7,64}$ ]]; then
            echo "Refusing rollback deployment: local verified release metadata is malformed or missing a valid commit SHA." >&2
            exit 1
          fi
          if ! git rev-parse --verify "${verified_commit}^{commit}" >/dev/null 2>&1; then
            echo "Refusing rollback deployment: local verified release metadata references invalid commit '$verified_commit'." >&2
            exit 1
          fi
          if [[ -n "$verified_prev" ]]; then
            if [[ ! "$verified_prev" =~ ^[0-9a-zA-Z._-]{7,64}$ ]]; then
              echo "Refusing rollback deployment: local verified release metadata contains malformed previous_commit." >&2
              exit 1
            fi
            if ! git rev-parse --verify "${verified_prev}^{commit}" >/dev/null 2>&1; then
              echo "Refusing rollback deployment: local verified release metadata references invalid previous_commit '$verified_prev'." >&2
              exit 1
            fi
          fi
        fi
      fi
      if [[ -f "$ROOT_DIR/dev_builds/release-metadata.json" ]]; then
        s3_live="$(cat "$ROOT_DIR/dev_builds/release-metadata.json" 2>/dev/null || true)"
        s3_live_source="local release metadata"
      fi
    fi

    live_commit="$(jq -er '.commit // .current_commit // empty' <<<"$s3_live" 2>/dev/null || true)"
    verified_commit="$(jq -er '.commit // empty' <<<"$s3_verified" 2>/dev/null || true)"
    verified_prev="$(jq -er '.previous_commit // empty' <<<"$s3_verified" 2>/dev/null || true)"

    if [[ -n "$verified_commit" ]]; then
      if [[ -n "$live_commit" && "$live_commit" == "$verified_commit" ]]; then
        # Live release is confirmed to be the verified release:
        # Roll back to the previous verified release before it
        resolved_sha="$verified_prev"
      else
        # Live release is unverified, differs from last verified release, or live marker is absent:
        # Roll back directly to the verified commit
        resolved_sha="$verified_commit"
      fi
    elif [[ -n "$s3_live" ]]; then
      live_source_label="${s3_live_source:-live release marker}"
      if [[ ! "$live_commit" =~ ^[0-9a-zA-Z._-]{7,64}$ ]]; then
        echo "Refusing rollback deployment: live release marker in $live_source_label is malformed or missing a valid commit SHA." >&2
        echo "Raw marker content: $s3_live" >&2
        exit 1
      fi
      if ! git rev-parse --verify "${live_commit}^{commit}" >/dev/null 2>&1; then
        echo "Refusing rollback deployment: live release marker in $live_source_label references invalid commit '$live_commit'." >&2
        exit 1
      fi
      live_prev="$(jq -er '.previous_commit // empty' <<<"$s3_live" 2>/dev/null || true)"
      if [[ -n "$live_prev" ]]; then
        if [[ ! "$live_prev" =~ ^[0-9a-zA-Z._-]{7,64}$ ]]; then
          echo "Refusing rollback deployment: live release marker in $live_source_label contains malformed previous_commit." >&2
          echo "Raw marker content: $s3_live" >&2
          exit 1
        fi
        if ! git rev-parse --verify "${live_prev}^{commit}" >/dev/null 2>&1; then
          echo "Refusing rollback deployment: live release marker in $live_source_label references invalid previous_commit '$live_prev'." >&2
          exit 1
        fi
      fi
      resolved_sha="$live_prev"
    fi

    if [[ -z "$resolved_sha" ]]; then
      echo "Refusing rollback deployment: no previous known-good commit recorded in local or durable release metadata." >&2
      exit 1
    fi
    ROLLBACK_TARGET_SHA="$resolved_sha"
  fi
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

if [[ -z "${AWS_REGION:-}" ]]; then
  echo "Refusing production deployment: AWS_REGION is required." >&2
  exit 1
fi

if [[ "$AWS_REGION" != "$EXPECTED_AWS_REGION" ]]; then
  echo "Refusing production deployment: AWS_REGION must be $EXPECTED_AWS_REGION, got '$AWS_REGION'." >&2
  exit 1
fi

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
