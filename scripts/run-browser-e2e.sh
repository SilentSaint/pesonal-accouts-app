#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
frontend_dir="$repo_root/frontend"

command -v node >/dev/null || { echo "Node.js 20+ is required" >&2; exit 1; }
command -v npm >/dev/null || { echo "npm is required; install Node.js 20+" >&2; exit 1; }

node_major="$(node --version | sed -E 's/^v([0-9]+).*$/\1/')"
if [ "$node_major" -lt 20 ]; then
  echo "Node.js 20+ is required; found $(node --version)" >&2
  exit 1
fi

browser="${E2E_BROWSER_EXECUTABLE:-}"
if [ -z "$browser" ]; then
  for candidate in /usr/bin/google-chrome /usr/bin/google-chrome-stable /usr/bin/chromium /usr/bin/chromium-browser /snap/bin/chromium; do
    if [ -x "$candidate" ]; then
      browser="$candidate"
      break
    fi
  done
fi
if [ -z "$browser" ]; then
  echo "A supported Chromium executable is required" >&2
  exit 1
fi

cd "$frontend_dir"
npm install --no-save --no-package-lock playwright@1.47.2
E2E_BROWSER_EXECUTABLE="$browser" node e2e_playwright_test.js
