#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly archive="$script_dir/lambda.zip"
readonly sources=(
  "$script_dir/index.js"
  "$script_dir/auth_identity.js"
  "$script_dir/dynamodb_pagination.js"
  "$script_dir/gmail_scan_query.js"
  "$script_dir/runtime_config.js"
  "$script_dir/analytics_reports.js"
  "$script_dir/websocket_authorizer.js"
  "$script_dir/websocket_sync.js"
)

build_archive() {
  rm -f "$1"
  python3 - "$1" "${sources[@]}" <<'PYTHON'
from pathlib import Path
from sys import argv
from zipfile import ZIP_STORED, ZipFile, ZipInfo

archive = Path(argv[1])
sources = [Path(source) for source in argv[2:]]

with ZipFile(archive, 'w', compression=ZIP_STORED) as zip_file:
    for source in sources:
        entry = ZipInfo(source.name, date_time=(1980, 1, 1, 0, 0, 0))
        entry.compress_type = ZIP_STORED
        entry.create_system = 3
        entry.create_version = 20
        entry.extract_version = 20
        entry.external_attr = 0o100644 << 16
        zip_file.writestr(entry, source.read_bytes())
PYTHON
}

if [[ "${1:-}" == "--check" ]]; then
  temporary_archive="$script_dir/.lambda-archive-check.zip"
  trap 'rm -f "$temporary_archive"' EXIT
  build_archive "$temporary_archive"
  if ! cmp -s "$temporary_archive" "$archive"; then
    echo "Lambda archive is stale. Run backend/lambda/build.sh before deploying."
    exit 1
  fi
  exit 0
fi

build_archive "$archive"
