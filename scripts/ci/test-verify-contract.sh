#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
verify_script="$repo_root/scripts/ci/verify"

test -x "$verify_script"
"$verify_script" --help | grep -Fq 'Run every repository verification command'
