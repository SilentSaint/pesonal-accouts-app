# Browser E2E runbook

The browser release gate uses Node.js 20 or newer, npm, the pinned Playwright
client `1.47.2`, and an installed Chromium-family browser. It does not add a
dependency to `frontend/pubspec.yaml`, `package.json`, or a lockfile.

From the repository root, build the release bundle and run:

```bash
cd frontend
flutter pub get
flutter build web --release
cd ..
scripts/run-browser-e2e.sh
```

The runner installs the pinned client with `npm install --no-save
--no-package-lock`, selects a standard system browser, and executes
`frontend/e2e_playwright_test.js`. Set `E2E_BROWSER_EXECUTABLE` when the
browser is installed elsewhere. The test writes screenshots only to ignored
working-tree paths; do not commit them.

GitHub Actions provisions Node.js 20 and calls the same runner, so local and CI
execution use the same dependency version, browser selection, and test entry
point. A machine without npm should use CI or install Node.js 20+ before
running the gate.
