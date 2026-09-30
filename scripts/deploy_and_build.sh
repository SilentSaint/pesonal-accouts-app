#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$ROOT_DIR/terraform"

if [[ "${AET_GUARDED_RELEASE:-}" != "YES" ]]; then
  echo "Refusing deployment: use scripts/manual_production_deploy.sh after its guards pass." >&2
  exit 1
fi

if [[ "$(git -C "$ROOT_DIR" branch --show-current)" != "main" ]]; then
  echo "Refusing deployment: checkout must be on main." >&2
  exit 1
fi

test -z "$(git -C "$ROOT_DIR" status --porcelain)" || {
  echo "Refusing deployment: working tree must be clean." >&2
  exit 1
}

: "${AWS_REGION:?Refusing deployment: AWS_REGION is required.}"
: "${AWS_ACCOUNT_ID:?Refusing deployment: AWS_ACCOUNT_ID is required.}"
export AWS_DEFAULT_REGION="$AWS_REGION"

actual_account="$(aws sts get-caller-identity --query Account --output text)"
if [[ "$actual_account" != "$AWS_ACCOUNT_ID" ]]; then
  echo "Refusing deployment: expected AWS account $AWS_ACCOUNT_ID, got $actual_account." >&2
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
  -var="aws_region=$AWS_REGION"
terraform -chdir="$TERRAFORM_DIR" show -json "$plan_file" > "$plan_json"

command -v jq >/dev/null || {
  echo "Refusing deployment: jq is required to read the reviewed Terraform plan." >&2
  exit 1
}

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

echo "[3/6] Building the reviewed web and Android artifacts before AWS mutation..."
api_base_url="${api_url%/}/api"
(
  cd "$ROOT_DIR/frontend"
  flutter build web --release --no-wasm-dry-run \
    --dart-define=API_BASE_URL="$api_base_url" \
    --dart-define=WEBSOCKET_SYNC_URL="$websocket_url"
  printf '{"commit":"%s"}\n' "$release_commit" > build/web/deployment-version.json
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
curl --fail --silent --show-error --retry 5 --retry-all-errors --retry-delay 5 \
  "${api_url%/}/api/health"

mkdir -p "$ROOT_DIR/dev_builds"
cp -r "$ROOT_DIR/frontend/build/web" "$ROOT_DIR/dev_builds/web-v1.0.1+2"
cp "$ROOT_DIR/frontend/build/app/outputs/flutter-apk/app-debug.apk" \
  "$ROOT_DIR/dev_builds/app-v1.0.1+2-debug.apk"

echo "=========================================================="
echo " Guarded deployment and live smoke verification completed"
echo " Mobile APK deliverable: $ROOT_DIR/dev_builds/app-v1.0.1+2-debug.apk"
echo " Web bundle deliverable: $ROOT_DIR/dev_builds/web-v1.0.1+2"
echo " API endpoint: ${api_url%/}"
echo "=========================================================="
