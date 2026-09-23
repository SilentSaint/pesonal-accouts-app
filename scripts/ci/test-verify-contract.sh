#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
verify_script="$repo_root/scripts/ci/verify-local-docker"

test -x "$verify_script"
"$verify_script" --help | grep -Fq 'Build the pinned local validation image'
