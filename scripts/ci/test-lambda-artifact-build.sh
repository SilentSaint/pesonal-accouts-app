#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifact_builder="$repo_root/scripts/ci/build-lambda-artifacts"

test -x "$artifact_builder"
"$artifact_builder"
unzip -t "$repo_root/backend/lambda/lambda.zip" >/dev/null
unzip -t "$repo_root/backend/build/lambda/transaction-command-lambda.zip" >/dev/null
