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

echo "Running local release gates before production deployment..."
(cd backend && ./gradlew test --no-daemon)
(cd frontend && flutter analyze)
(cd frontend && flutter test)

aws sts get-caller-identity >/dev/null || {
  echo "Refusing production deployment: AWS credentials are unavailable or expired." >&2
  exit 1
}

echo "All manual deployment guards passed for $(git rev-parse HEAD)."
exec "$SCRIPT_DIR/deploy_and_build.sh"
