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

echo "=========================================================="
echo " Starting guarded production deployment for $release_commit"
echo "=========================================================="

echo "[1/5] Building reviewed Lambda artifacts..."
"$ROOT_DIR/backend/lambda/build.sh"
"$ROOT_DIR/backend/gradlew" -p "$ROOT_DIR/backend" lambdaZip --no-daemon

echo "[2/5] Applying reviewed Terraform infrastructure..."
terraform -chdir="$TERRAFORM_DIR" init -input=false
terraform -chdir="$TERRAFORM_DIR" apply \
  -auto-approve \
  -input=false \
  -var="aws_region=$AWS_REGION"

api_url="$(terraform -chdir="$TERRAFORM_DIR" output -raw api_gateway_url)"
websocket_url="$(terraform -chdir="$TERRAFORM_DIR" output -raw websocket_sync_url)"
bucket="$(terraform -chdir="$TERRAFORM_DIR" output -raw s3_web_bucket_name)"
distribution_id="$(terraform -chdir="$TERRAFORM_DIR" output -raw cloudfront_distribution_id)"
cloudfront_url="$(terraform -chdir="$TERRAFORM_DIR" output -raw cloudfront_web_url)"

echo "[3/5] Building the reviewed web and Android artifacts..."
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

echo "[4/5] Publishing the web artifact and invalidating CloudFront..."
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

echo "[5/5] Verifying the live deployment..."
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
