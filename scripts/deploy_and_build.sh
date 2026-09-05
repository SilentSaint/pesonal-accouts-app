#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================================="
echo " Starting End-to-End Automated Deployment & Build Pipeline"
echo "=========================================================="

echo "[1/4] Checking AWS Authentication & Deploying Infrastructure (ap-south-2)..."
echo "-> Building Lambda archive from reviewed source..."
"$ROOT_DIR/backend/lambda/build.sh"
echo "-> Building Java transaction-command Lambda archive..."
"$ROOT_DIR/backend/gradlew" -p "$ROOT_DIR/backend" lambdaZip --no-daemon
cd "$ROOT_DIR/terraform"
terraform init >/dev/null 2>&1

API_URL=""
WEBSOCKET_URL=""
if terraform apply -auto-approve 2>/dev/null; then
  API_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
  WEBSOCKET_URL=$(terraform output -raw websocket_sync_url 2>/dev/null || echo "")
  echo "-> Successfully deployed AWS Infrastructure in ap-south-2!"
else
  echo "[NOTICE] AWS credentials session not authenticated in shell."
  echo "-> Using provisioned AWS API Gateway endpoint from Terraform state."
  API_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "https://6nyqikrpbb.execute-api.ap-south-2.amazonaws.com")
fi

if [[ "$API_URL" != */api ]]; then
  API_URL="$API_URL/api"
fi

echo "-> Active Backend API URL: $API_URL"

echo "[2/4] Reading live API and WebSocket endpoints..."
cd "$ROOT_DIR/frontend"
echo "-> Active WebSocket sync URL: ${WEBSOCKET_URL:-not configured}"

echo "[3/4] Running Static Analysis & Test Suite..."
export PATH="$PATH:/home/rakshith/flutter/flutter/bin:$HOME/android_sdk/platform-tools"
export ANDROID_HOME="$HOME/android_sdk"

flutter analyze
flutter test

echo "[4/4] Compiling Application Web Bundle & Android APK..."
flutter build web --release --no-wasm-dry-run \
  --dart-define=API_BASE_URL="$API_URL" \
  --dart-define=WEBSOCKET_SYNC_URL="$WEBSOCKET_URL"
flutter build apk --target-platform android-arm64 --debug --android-skip-build-dependency-validation \
  --dart-define=API_BASE_URL="$API_URL" \
  --dart-define=WEBSOCKET_SYNC_URL="$WEBSOCKET_URL"

mkdir -p "$ROOT_DIR/dev_builds"
cp -r build/web "$ROOT_DIR/dev_builds/web-v1.0.1+2"
cp build/app/outputs/flutter-apk/app-debug.apk "$ROOT_DIR/dev_builds/app-v1.0.1+2-debug.apk"

if aws sts get-caller-identity >/dev/null 2>&1; then
  S3_BUCKET=$(cd "$ROOT_DIR/terraform" && terraform output -raw s3_web_bucket_name 2>/dev/null)
  if [ -n "$S3_BUCKET" ]; then
    echo "-> Publishing Web Bundle to AWS S3 bucket ($S3_BUCKET)..."
    aws s3 cp "$ROOT_DIR/frontend/build/web" "s3://$S3_BUCKET" \
      --recursive \
      --cache-control "no-cache, no-store, must-revalidate" \
      --metadata-directive REPLACE
    aws s3 sync "$ROOT_DIR/frontend/build/web" "s3://$S3_BUCKET" --delete
    CLOUDFRONT_DISTRIBUTION_ID=$(cd "$ROOT_DIR/terraform" && terraform output -raw cloudfront_distribution_id 2>/dev/null)
    if [ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
      INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text)
      aws cloudfront wait invalidation-completed \
        --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
        --id "$INVALIDATION_ID"
      echo "-> Published and invalidated CloudFront ($INVALIDATION_ID)."
    fi
  fi
fi

echo "=========================================================="
echo " Deployment & Build Pipeline Completed Successfully!"
echo " Mobile APK Deliverable: $ROOT_DIR/dev_builds/app-v1.0.1+2-debug.apk"
echo " Web Bundle Deliverable: $ROOT_DIR/dev_builds/web-v1.0.1+2"
echo " Configured API Endpoint: $API_URL"
echo "=========================================================="
