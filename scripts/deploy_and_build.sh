#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${TARGET_DIR:-$(dirname "$SCRIPT_DIR")}"
TERRAFORM_DIR="$ROOT_DIR/terraform"

if [[ "${AET_GUARDED_RELEASE:-}" != "YES" ]]; then
  echo "Refusing deployment: use scripts/manual_production_deploy.sh after its guards pass." >&2
  exit 1
fi

if [[ -n "${ROLLBACK_TARGET_SHA:-}" ]]; then
  rollback_rev="$(git -C "$ROOT_DIR" rev-parse --verify "${ROLLBACK_TARGET_SHA}^{commit}" 2>/dev/null)" || {
    echo "Refusing deployment: invalid ROLLBACK_TARGET_SHA '$ROLLBACK_TARGET_SHA'." >&2
    exit 1
  }
  if ! git -C "$ROOT_DIR" merge-base --is-ancestor "$rollback_rev" origin/main; then
    echo "Refusing deployment: commit $rollback_rev is not contained in origin/main." >&2
    exit 1
  fi
  current_rev="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  if [[ "$current_rev" != "$rollback_rev" ]]; then
    echo "Refusing deployment: HEAD ($current_rev) does not match ROLLBACK_TARGET_SHA ($rollback_rev)." >&2
    exit 1
  fi
else
  if [[ "$(git -C "$ROOT_DIR" branch --show-current)" != "main" ]]; then
    echo "Refusing deployment: checkout must be on main." >&2
    exit 1
  fi
fi

test -z "$(git -C "$ROOT_DIR" status --porcelain)" || {
  echo "Refusing deployment: working tree must be clean." >&2
  exit 1
}

: "${AWS_REGION:?Refusing deployment: AWS_REGION is required.}"
: "${AWS_ACCOUNT_ID:?Refusing deployment: AWS_ACCOUNT_ID is required.}"
readonly EXPECTED_AWS_REGION="ap-south-2"
readonly EXPECTED_AWS_ACCOUNT_ID="727118420276"
readonly EXPECTED_TERRAFORM_ENVIRONMENT="production"

if [[ "${AWS_REGION:-}" != "$EXPECTED_AWS_REGION" ]]; then
  echo "Refusing deployment: AWS_REGION must be $EXPECTED_AWS_REGION, got '${AWS_REGION:-empty}'." >&2
  exit 1
fi

if [[ "${AWS_ACCOUNT_ID:-}" != "$EXPECTED_AWS_ACCOUNT_ID" ]]; then
  echo "Refusing deployment: AWS_ACCOUNT_ID must be $EXPECTED_AWS_ACCOUNT_ID, got '${AWS_ACCOUNT_ID:-empty}'." >&2
  exit 1
fi

export AWS_DEFAULT_REGION="$AWS_REGION"

actual_account="$(aws sts get-caller-identity --query Account --output text)"
if [[ "$actual_account" != "$EXPECTED_AWS_ACCOUNT_ID" ]]; then
  echo "Refusing deployment: expected AWS account $EXPECTED_AWS_ACCOUNT_ID, got $actual_account." >&2
  exit 1
fi

release_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
umask 077
plan_file="$(mktemp "${TMPDIR:-/tmp}/automatic-expense-tracker-release-plan.XXXXXX")"
plan_json="${plan_file}.json"
rm -f "$plan_file"
cleanup_plan_files() {
  rm -f "$plan_file" "$plan_json"
}
trap cleanup_plan_files EXIT

echo "=========================================================="
echo " Starting guarded production deployment for $release_commit"
echo "=========================================================="

echo "[1/6] Building reviewed Lambda artifacts..."
"$ROOT_DIR/backend/lambda/build.sh"
"$ROOT_DIR/backend/gradlew" -p "$ROOT_DIR/backend" lambdaZip --no-daemon

echo "[2/6] Planning reviewed Terraform infrastructure..."
terraform -chdir="$TERRAFORM_DIR" init -input=false
terraform -chdir="$TERRAFORM_DIR" plan \
  -input=false \
  -out="$plan_file" \
  -var="aws_region=$AWS_REGION" \
  -var="environment=$EXPECTED_TERRAFORM_ENVIRONMENT"
terraform -chdir="$TERRAFORM_DIR" show -json "$plan_file" > "$plan_json"

command -v jq >/dev/null || {
  echo "Refusing deployment: jq is required to read the reviewed Terraform plan." >&2
  exit 1
}

planned_table_deletion_protection="$(jq -r '
  (.planned_values.root_module.resources[]? | select(.address == "aws_dynamodb_table.expense_tracker_data") | .values.deletion_protection_enabled) // empty
' "$plan_json")"

if [[ "$planned_table_deletion_protection" != "true" ]]; then
  echo "Refusing deployment: production DynamoDB table ExpenseTrackerData must have deletion protection enabled in the reviewed plan (got '${planned_table_deletion_protection:-empty}')." >&2
  exit 1
fi

planned_output() {
  local output_name="$1"
  jq -er --arg output_name "$output_name" \
    '.planned_values.outputs[$output_name].value // empty' "$plan_json"
}


api_url="$(planned_output api_gateway_url)"
websocket_url="$(planned_output websocket_sync_url)"
bucket="$(planned_output s3_web_bucket_name)"
distribution_id="$(planned_output cloudfront_distribution_id)"
cloudfront_url="$(planned_output cloudfront_web_url)"

validate_commit_sha() {
  local sha="$1"
  local label="$2"
  local source="$3"

  if [[ ! "$sha" =~ ^[0-9a-zA-Z._-]{7,64}$ ]]; then
    if [[ "$label" == "commit SHA" ]]; then
      echo "Refusing deployment: $source is malformed or missing a valid commit SHA." >&2
    else
      echo "Refusing deployment: $source contains malformed $label." >&2
    fi
    exit 1
  fi
  if ! git -C "$ROOT_DIR" rev-parse --verify "${sha}^{commit}" >/dev/null 2>&1; then
    echo "Refusing deployment: $source references invalid $label '$sha'." >&2
    exit 1
  fi
  if ! (git -C "$ROOT_DIR" merge-base --is-ancestor "$sha" "$release_commit" 2>/dev/null || git -C "$ROOT_DIR" merge-base --is-ancestor "$sha" origin/main 2>/dev/null); then
    echo "Refusing deployment: $source contains $label '$sha' not contained in release history." >&2
    exit 1
  fi
}

resolve_previous_commit() {
  local existing_commit="$1"
  local existing_prev="$2"
  local is_verified="${3:-1}"

  if [[ "$existing_commit" == "$release_commit" ]]; then
    echo "$existing_prev"
  elif [[ -n "${ROLLBACK_TARGET_SHA:-}" ]]; then
    # In rollback mode, existing_commit is the rejected release being rolled back from.
    # Never rotate the rejected release into previous_commit.
    if [[ -n "$existing_prev" && "$existing_prev" != "$release_commit" && "$existing_prev" != "$existing_commit" ]]; then
      if git -C "$ROOT_DIR" merge-base --is-ancestor "$existing_prev" "$release_commit" 2>/dev/null; then
        echo "$existing_prev"
        return
      fi
    fi
    # Omit previous_commit unless verified release history identifies one.
    # Do not derive a known-good release from Git ancestry.
    echo ""
  else
    if [[ "$is_verified" -eq 1 ]]; then
      echo "$existing_commit"
    else
      # When last-verified-release.json does not exist, existing_commit is an unverified publication.
      # If existing_prev is recorded, use that known-good commit; otherwise omit previous_commit.
      if [[ -n "$existing_prev" ]]; then
        echo "$existing_prev"
      else
        echo ""
      fi
    fi
  fi
}

echo "[3/6] Building the reviewed web and Android artifacts before AWS mutation..."
previous_commit=""
if [[ -n "${bucket:-}" ]]; then
  s3_err_file="$(mktemp /tmp/aet-s3-read-err.XXXXXX)"
  s3_marker_output=""
  s3_status=0
  s3_marker_output="$(aws s3 cp "s3://$bucket/last-verified-release.json" - 2>"$s3_err_file")" || s3_status=$?
  s3_read_error="$(cat "$s3_err_file" 2>/dev/null || true)"
  rm -f "$s3_err_file"

  if [[ "$s3_status" -eq 0 ]]; then
    existing_commit="$(jq -er '.commit // empty' <<<"$s3_marker_output" 2>/dev/null || true)"
    existing_prev="$(jq -er '.previous_commit // empty' <<<"$s3_marker_output" 2>/dev/null || true)"
    validate_commit_sha "$existing_commit" "commit SHA" "live verified release marker in s3://$bucket/last-verified-release.json"
    if [[ -n "$existing_prev" ]]; then
      validate_commit_sha "$existing_prev" "previous_commit" "live verified release marker in s3://$bucket/last-verified-release.json"
    fi
    previous_commit="$(resolve_previous_commit "$existing_commit" "$existing_prev" 1)"
  else
    if grep -Eqi '(NoSuchBucket|bucket.*does not exist)' <<<"$s3_read_error" || ! grep -Eqi '(404|NoSuchKey|does not exist)' <<<"$s3_read_error"; then
      echo "Refusing deployment: failed to read verified release marker from s3://$bucket/last-verified-release.json." >&2
      echo "$s3_read_error" >&2
      exit 1
    fi

    # Fall back to deployment-version.json if last-verified-release.json does not exist yet
    s3_err_file="$(mktemp /tmp/aet-s3-read-err.XXXXXX)"
    s3_marker_output=""
    s3_status=0
    s3_marker_output="$(aws s3 cp "s3://$bucket/deployment-version.json" - 2>"$s3_err_file")" || s3_status=$?
    s3_read_error="$(cat "$s3_err_file" 2>/dev/null || true)"
    rm -f "$s3_err_file"

    if [[ "$s3_status" -eq 0 ]]; then
      existing_commit="$(jq -er '.commit // empty' <<<"$s3_marker_output" 2>/dev/null || true)"
      existing_prev="$(jq -er '.previous_commit // empty' <<<"$s3_marker_output" 2>/dev/null || true)"
      validate_commit_sha "$existing_commit" "commit SHA" "live deployment marker in s3://$bucket/deployment-version.json"
      if [[ -n "$existing_prev" ]]; then
        validate_commit_sha "$existing_prev" "previous_commit" "live deployment marker in s3://$bucket/deployment-version.json"
      fi
      previous_commit="$(resolve_previous_commit "$existing_commit" "$existing_prev" 0)"
    else
      if ! grep -Eqi '(NoSuchBucket|bucket.*does not exist)' <<<"$s3_read_error" && grep -Eqi '(404|NoSuchKey|does not exist)' <<<"$s3_read_error"; then
        echo "No existing live deployment marker in S3 (initial bootstrap deployment)."
        if [[ -f "$ROOT_DIR/dev_builds/release-metadata.json" ]]; then
          existing_commit="$(jq -er '.current_commit // empty' "$ROOT_DIR/dev_builds/release-metadata.json" 2>/dev/null || true)"
          existing_prev="$(jq -er '.previous_commit // empty' "$ROOT_DIR/dev_builds/release-metadata.json" 2>/dev/null || true)"
          if [[ -n "$existing_commit" ]]; then
            validate_commit_sha "$existing_commit" "commit SHA" "local release metadata"
            if [[ -n "$existing_prev" ]]; then
              validate_commit_sha "$existing_prev" "previous_commit" "local release metadata"
            fi
            previous_commit="$(resolve_previous_commit "$existing_commit" "$existing_prev" 0)"
          fi
        fi
      else
        echo "Refusing deployment: failed to read live deployment marker from s3://$bucket/deployment-version.json." >&2
        echo "$s3_read_error" >&2
        exit 1
      fi
    fi
  fi
fi

api_base_url="${api_url%/}/api"
(
  cd "$ROOT_DIR/frontend"
  flutter build web --release --no-wasm-dry-run \
    --dart-define=API_BASE_URL="$api_base_url" \
    --dart-define=WEBSOCKET_SYNC_URL="$websocket_url"
  if [[ -n "$previous_commit" ]]; then
    printf '{"commit":"%s","previous_commit":"%s"}\n' "$release_commit" "$previous_commit" > build/web/deployment-version.json
    printf '{"current_commit":"%s","previous_commit":"%s","deployed_at":"%s"}\n' \
      "$release_commit" "$previous_commit" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > build/web/release-metadata.json
  else
    printf '{"commit":"%s"}\n' "$release_commit" > build/web/deployment-version.json
    printf '{"current_commit":"%s","deployed_at":"%s"}\n' \
      "$release_commit" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > build/web/release-metadata.json
  fi
  flutter build apk --target-platform android-arm64 --debug \
    --android-skip-build-dependency-validation \
    --dart-define=API_BASE_URL="$api_base_url" \
    --dart-define=WEBSOCKET_SYNC_URL="$websocket_url"
)

echo "[4/6] Applying the exact reviewed Terraform plan..."
terraform -chdir="$TERRAFORM_DIR" apply \
  -auto-approve \
  -input=false \
  "$plan_file"

assert_output_matches_plan() {
  local output_name="$1"
  local expected_value="$2"
  local actual_value
  actual_value="$(terraform -chdir="$TERRAFORM_DIR" output -raw "$output_name")"
  if [[ "$actual_value" != "$expected_value" ]]; then
    echo "Refusing publication: Terraform output $output_name changed after applying the saved plan." >&2
    echo "Expected: $expected_value" >&2
    echo "Actual:   $actual_value" >&2
    exit 1
  fi
}

assert_output_matches_plan api_gateway_url "$api_url"
assert_output_matches_plan websocket_sync_url "$websocket_url"
assert_output_matches_plan s3_web_bucket_name "$bucket"
assert_output_matches_plan cloudfront_distribution_id "$distribution_id"
assert_output_matches_plan cloudfront_web_url "$cloudfront_url"

echo "[5/6] Publishing the web artifact and invalidating CloudFront..."
aws s3 sync "$ROOT_DIR/frontend/build/web" "s3://$bucket" \
  --delete \
  --exclude 'last-verified-release.json' \
  --cache-control 'no-cache, no-store, must-revalidate' \
  --region "$AWS_REGION"
invalidation_id="$(aws cloudfront create-invalidation \
  --distribution-id "$distribution_id" \
  --paths '/*' \
  --query 'Invalidation.Id' \
  --output text)"
aws cloudfront wait invalidation-completed \
  --distribution-id "$distribution_id" \
  --id "$invalidation_id"

echo "[6/6] Verifying the live deployment..."
release_marker_url="${cloudfront_url%/}/deployment-version.json?release=$release_commit"
curl --fail --silent --show-error --retry 5 --retry-all-errors --retry-delay 5 \
  "$release_marker_url" | grep -F "\"commit\":\"$release_commit\""
release_metadata_url="${cloudfront_url%/}/release-metadata.json?release=$release_commit"
curl --fail --silent --show-error --retry 5 --retry-all-errors --retry-delay 5 \
  "$release_metadata_url" | grep -F "\"current_commit\":\"$release_commit\""
curl --fail --silent --show-error --retry 5 --retry-all-errors --retry-delay 5 \
  "${api_url%/}/api/health"

verified_tmp="$(mktemp /tmp/aet-verified-release.XXXXXX)"
if [[ -n "$previous_commit" ]]; then
  printf '{"commit":"%s","previous_commit":"%s","verified_at":"%s"}\n' \
    "$release_commit" "$previous_commit" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$verified_tmp"
else
  printf '{"commit":"%s","verified_at":"%s"}\n' \
    "$release_commit" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$verified_tmp"
fi
aws s3 cp "$verified_tmp" "s3://$bucket/last-verified-release.json" \
  --cache-control 'no-cache, no-store, must-revalidate' \
  --region "$AWS_REGION"
rm -f "$verified_tmp"

mkdir -p "$ROOT_DIR/dev_builds"
cp -r "$ROOT_DIR/frontend/build/web" "$ROOT_DIR/dev_builds/web-v1.0.1+2"
cp "$ROOT_DIR/frontend/build/app/outputs/flutter-apk/app-debug.apk" \
  "$ROOT_DIR/dev_builds/app-v1.0.1+2-debug.apk"
if [[ -f "$ROOT_DIR/frontend/build/web/release-metadata.json" ]]; then
  cp "$ROOT_DIR/frontend/build/web/release-metadata.json" "$ROOT_DIR/dev_builds/release-metadata.json"
fi
if [[ -n "$previous_commit" ]]; then
  printf '{"commit":"%s","previous_commit":"%s","verified_at":"%s"}\n' \
    "$release_commit" "$previous_commit" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$ROOT_DIR/dev_builds/last-verified-release.json"
else
  printf '{"commit":"%s","verified_at":"%s"}\n' \
    "$release_commit" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$ROOT_DIR/dev_builds/last-verified-release.json"
fi

echo "=========================================================="
echo " Guarded deployment and live smoke verification completed"
echo " Mobile APK deliverable: $ROOT_DIR/dev_builds/app-v1.0.1+2-debug.apk"
echo " Web bundle deliverable: $ROOT_DIR/dev_builds/web-v1.0.1+2"
echo " Release metadata: $ROOT_DIR/dev_builds/release-metadata.json"
echo " API endpoint: ${api_url%/}"
echo "=========================================================="
