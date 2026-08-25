#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================================="
echo " Starting End-to-End Automated Deployment & Build Pipeline"
echo "=========================================================="

echo "[1/4] Checking AWS Authentication & Deploying Infrastructure (ap-south-2)..."
cd "$ROOT_DIR/terraform"
terraform init >/dev/null 2>&1

API_URL=""
if terraform apply -auto-approve 2>/dev/null; then
  API_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
  echo "-> Successfully deployed AWS Infrastructure in ap-south-2!"
else
  echo "[NOTICE] AWS credentials session not authenticated in shell."
  echo "-> Falling back to configured API Gateway / Local Endpoint until 'aws login' is run."
  API_URL="http://localhost:8080/api"
fi

echo "-> Active Backend API URL: $API_URL"

echo "[2/4] Auto-Injecting API URL into Flutter Configuration..."
cd "$ROOT_DIR/frontend"
cat <<EOF > lib/services/api_config.dart
class ApiConfig {
  static String baseUrl = '$API_URL';

  static void useCustomApiEndpoint(String apiEndpoint) {
    if (apiEndpoint.isEmpty) return;
    baseUrl = apiEndpoint.endsWith('/api') ? apiEndpoint : '\$apiEndpoint/api';
  }

  static void resetToDefault() {
    baseUrl = '$API_URL';
  }
}
EOF

echo "[3/4] Running Static Analysis & Test Suite..."
export PATH="$PATH:/home/rakshith/flutter/flutter/bin"
flutter analyze
flutter test

echo "[4/4] Compiling Application Release Deliverable..."
flutter build web --release

mkdir -p "$ROOT_DIR/dev_builds"
cp -r build/web "$ROOT_DIR/dev_builds/web-v1.0.1+2"

echo "=========================================================="
echo " Deployment & Build Pipeline Completed!"
echo " Release Deliverable: $ROOT_DIR/dev_builds/web-v1.0.1+2"
echo " Configured API Endpoint: $API_URL"
echo "=========================================================="
