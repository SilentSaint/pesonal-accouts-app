#!/bin/bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

record_phase() {
  PHASE="$1"
  node "$SCRIPT_DIR/release_evidence.js" status "$RELEASE_DIR" "$RELEASE_STATUS" "$PHASE"
}

finish() {
  local code="$1"
  if [[ "$code" != 0 ]]; then
    node "$SCRIPT_DIR/release_evidence.js" status "$RELEASE_DIR" failed "$PHASE" "$code" || \
      echo "Could not persist failure status; preserve this release directory." >&2
    echo "Release failed during $PHASE. Private evidence: $RELEASE_DIR" >&2
    echo "Lease acquisition was attempted with owner $RELEASE_TOKEN; it is never auto-cleared on failure. Follow owner recovery in the runbook." >&2
  fi
}

private_terraform() {
  local phase="$1"
  shift
  terraform "$@" >"$RELEASE_DIR/terraform-$phase.log" 2>&1 || {
    echo "Terraform $phase failed; inspect private evidence: $RELEASE_DIR/terraform-$phase.log" >&2
    return 1
  }
}

check_seal() {
  local actual
  actual="$(preparation_seal && sha256sum "$RELEASE_DIR/terraform.plan" "$RELEASE_DIR/plan-review.json")"
  test "$actual" = "$CANDIDATE_SEAL" || {
    echo "Saved plan or candidate evidence changed after review." >&2
    return 1
  }
}

preparation_seal() {
  sha256sum "$RELEASE_DIR/source.tar" "$RELEASE_DIR/source.json" \
    "$RELEASE_DIR/provenance.json" "$RELEASE_DIR/manifest.json"
}

required_output() {
  local value
  value="$(terraform output -raw "$1")" || return 1
  if [[ -z "$value" || "$value" == "null" || "$value" == "None" ]]; then
    echo "Required Terraform output '$1' is missing; refusing production deployment." >&2
    return 1
  fi
  printf '%s' "$value"
}

check_source() {
  local current_sha status
  current_sha="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  status="$(git -C "$ROOT_DIR" status --porcelain)"
  if [[ "$current_sha" != "$SOURCE_SHA" || -n "$status" ]]; then
    echo "Refusing production deployment: candidate source changed during preparation." >&2
    return 1
  fi
  git -C "$ROOT_DIR" fetch --quiet origin main
  test "$SOURCE_SHA" = "$(git -C "$ROOT_DIR" rev-parse origin/main)" || {
    echo "Refusing production deployment: main advanced during preparation; review the new candidate." >&2
    return 1
  }
}

check_identity() {
  local actual_account actual_arn expected_role
  [[ "${AWS_ACCOUNT_ID:-}" =~ ^[0-9]{12}$ ]] || {
    echo "Refusing production deployment: AWS_ACCOUNT_ID must identify the expected AWS account." >&2
    return 1
  }
  [[ "${AWS_REGION:-}" == "ap-south-2" && "${AWS_DEFAULT_REGION:-ap-south-2}" == "$AWS_REGION" ]] || {
    echo "Refusing production deployment: configure region ap-south-2 consistently." >&2
    return 1
  }
  [[ "${AWS_DEPLOY_ROLE_ARN:-}" == "arn:aws:iam::$AWS_ACCOUNT_ID:role/"* ]] || {
    echo "Refusing production deployment: configure the expected assumed deployment role." >&2
    return 1
  }
  actual_account="$(aws sts get-caller-identity --query Account --output text)" || {
    echo "Refusing production deployment: AWS credentials are unavailable or expired." >&2
    return 1
  }
  test "$actual_account" = "$AWS_ACCOUNT_ID" || {
    echo "Refusing production deployment: credentials belong to a different AWS account." >&2
    return 1
  }
  actual_arn="$(aws sts get-caller-identity --query Arn --output text)"
  expected_role="${AWS_DEPLOY_ROLE_ARN##*/}"
  [[ -n "$expected_role" && "$actual_arn" == "arn:aws:sts::$AWS_ACCOUNT_ID:assumed-role/$expected_role/"* ]] || {
    echo "Refusing production deployment: identity must assume the configured deployment role." >&2
    return 1
  }
}

if [[ "${PRODUCTION_DEPLOY_APPROVED:-}" != "YES" ]]; then
  echo "Refusing production deployment: set PRODUCTION_DEPLOY_APPROVED=YES after explicit owner approval." >&2
  exit 1
fi

cd "$ROOT_DIR"
SOURCE_SHA="$(git rev-parse HEAD)"
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  test "${GITHUB_REF:-}" = "refs/heads/main" && test "${GITHUB_SHA:-}" = "$SOURCE_SHA" || {
    echo "Refusing production deployment: CI must use its gated main revision." >&2
    exit 1
  }
else
  test "$(git branch --show-current)" = "main" || {
    echo "Refusing production deployment: checkout must be on main." >&2
    exit 1
  }
fi
git fetch --quiet origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || {
  echo "Refusing production deployment: local main must exactly match origin/main." >&2
  exit 1
}
SOURCE_STATUS="$(git status --porcelain)"
test -z "$SOURCE_STATUS" || {
  echo "Refusing production deployment: working tree must be clean." >&2
  exit 1
}

check_identity
export AWS_DEFAULT_REGION="$AWS_REGION"
while IFS= read -r name; do
  if [[ "$name" == TF_CLI_ARGS* ]]; then
    echo "Refusing production deployment: Terraform CLI environment configuration overrides are not permitted." >&2
    exit 1
  fi
done < <(compgen -e)
test "${TF_WORKSPACE:-default}" = "default" || {
  echo "Refusing production deployment: Terraform workspace must be default for the existing state." >&2
  exit 1
}
export TF_WORKSPACE=default
RELEASE_TOKEN="$(node -p 'require("node:crypto").randomUUID()')"
mkdir -p "$ROOT_DIR/dev_builds/releases"
RELEASE_DIR="$(mktemp -d "$ROOT_DIR/dev_builds/releases/$SOURCE_SHA-XXXXXX")"
export TF_DATA_DIR="$RELEASE_DIR/terraform-data"
PHASE="lease"
RELEASE_STATUS="preparing"
trap 'finish $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
node "$SCRIPT_DIR/release_evidence.js" source "$RELEASE_DIR" "$ROOT_DIR" "$SOURCE_SHA" "$RELEASE_TOKEN"
record_phase lease
node "$SCRIPT_DIR/release_lease.js" acquire "$RELEASE_TOKEN" "$SOURCE_SHA"
echo "Preparing release $SOURCE_SHA. Private evidence: $RELEASE_DIR"
record_phase infrastructure-readiness
cd "$ROOT_DIR/terraform"
private_terraform init init -input=false

API_URL="$(required_output api_gateway_url)"
API_GATEWAY_URL="$API_URL"
WEBSOCKET_URL="$(required_output websocket_sync_url)"
S3_BUCKET="$(required_output s3_web_bucket_name)"
CLOUDFRONT_DISTRIBUTION_ID="$(required_output cloudfront_distribution_id)"
CLOUDFRONT_URL="$(required_output cloudfront_web_url)"

if [[ "$API_URL" != */api ]]; then
  API_URL="$API_URL/api"
fi

export API_BASE_URL="$API_URL" WEBSOCKET_SYNC_URL="$WEBSOCKET_URL"
node "$SCRIPT_DIR/release_evidence.js" configuration "$RELEASE_DIR"
record_phase readiness
echo "Running all release gates against the endpoint-configured candidate..."
"$SCRIPT_DIR/ci/verify"

cd "$ROOT_DIR/frontend"
record_phase apk
flutter build apk --target-platform android-arm64 --debug \
  --dart-define=API_BASE_URL="$API_URL" \
  --dart-define=WEBSOCKET_SYNC_URL="$WEBSOCKET_URL"

check_source
node "$SCRIPT_DIR/release_artifacts.js" "$ROOT_DIR" "$SOURCE_SHA" "$RELEASE_DIR" >/dev/null
PREPARATION_SEAL="$(preparation_seal)"
RELEASE_STATUS="prepared"
record_phase plan

cd "$ROOT_DIR/terraform"
private_terraform plan plan -input=false -lock-timeout=60s -out="$RELEASE_DIR/terraform.plan"
PLAN_SEAL="$(sha256sum "$RELEASE_DIR/terraform.plan")"
terraform show -json "$RELEASE_DIR/terraform.plan" >"$RELEASE_DIR/terraform-plan.json"
test "$PLAN_SEAL" = "$(sha256sum "$RELEASE_DIR/terraform.plan")" || {
  echo "Saved plan changed while preparing its review." >&2
  exit 1
}
test "$PREPARATION_SEAL" = "$(preparation_seal)" || {
  echo "Prepared candidate or source evidence changed during planning." >&2
  exit 1
}
node "$SCRIPT_DIR/release_plan.js" "$RELEASE_DIR" \
  "$API_GATEWAY_URL" "$WEBSOCKET_URL" "$S3_BUCKET" "$CLOUDFRONT_DISTRIBUTION_ID" "$CLOUDFRONT_URL"
CANDIDATE_SEAL="$(preparation_seal && sha256sum "$RELEASE_DIR/terraform.plan" "$RELEASE_DIR/plan-review.json")"
check_source
check_identity
node "$SCRIPT_DIR/release_lease.js" check "$RELEASE_TOKEN"
node "$SCRIPT_DIR/release_artifacts.js" verify-artifacts "$ROOT_DIR" "$RELEASE_DIR"
check_seal
record_phase apply
private_terraform apply apply -input=false -lock-timeout=60s "$RELEASE_DIR/terraform.plan"

record_phase lambda-verification
check_identity
check_source
node "$SCRIPT_DIR/release_lease.js" check "$RELEASE_TOKEN"
node "$SCRIPT_DIR/release_artifacts.js" verify-artifacts "$ROOT_DIR" "$RELEASE_DIR"
check_seal
node "$SCRIPT_DIR/release_lambdas.js" "$RELEASE_DIR"
record_phase publication
node "$SCRIPT_DIR/release_artifacts.js" verify-artifacts "$ROOT_DIR" "$RELEASE_DIR"
check_seal
echo "-> Publishing Web Bundle to AWS S3 bucket ($S3_BUCKET)..."
aws s3 sync "$RELEASE_DIR/web" "s3://$S3_BUCKET" --delete \
  --cache-control "no-cache, no-store, must-revalidate"
record_phase invalidation
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
  --paths "/*" \
  --query 'Invalidation.Id' \
  --output text)
aws cloudfront wait invalidation-completed \
  --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
  --id "$INVALIDATION_ID"
record_phase live-smoke
curl --fail --silent --show-error --max-time 30 \
  --retry 5 --retry-all-errors --retry-delay 5 \
  "$CLOUDFRONT_URL/deployment-version.json?release=$(basename "$RELEASE_DIR")" \
  | node "$SCRIPT_DIR/release_artifacts.js" verify-version "$RELEASE_DIR"
curl --fail --silent --show-error --max-time 30 \
  --retry 5 --retry-all-errors --retry-delay 5 "$API_URL/health"
echo "-> Published and invalidated CloudFront ($INVALIDATION_ID)."
check_identity
check_seal
node "$SCRIPT_DIR/release_artifacts.js" verify-artifacts "$ROOT_DIR" "$RELEASE_DIR"
record_phase lease-release
node "$SCRIPT_DIR/release_lease.js" release "$RELEASE_TOKEN"
RELEASE_STATUS="verified"
record_phase complete

echo "=========================================================="
echo " Deployment & Build Pipeline Completed Successfully!"
echo " Release evidence: $RELEASE_DIR/manifest.json"
echo " Mobile APK Deliverable: $RELEASE_DIR/app-debug.apk"
echo " Web Bundle Deliverable: $RELEASE_DIR/web"
echo " Configured API Endpoint: $API_URL"
echo "=========================================================="
