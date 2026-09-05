#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
expected_wrapper="backend/gradle/wrapper/gradle-wrapper.jar"

git -C "$repo_root" ls-files --error-unmatch "$expected_wrapper" >/dev/null
"$repo_root/scripts/ci/generated-artifact-check"
