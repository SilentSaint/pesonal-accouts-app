const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

test('local validation is the canonical non-mutating verification seam', () => {
  const verifier = read('scripts/ci/verify-local');
  const dockerVerifier = read('scripts/ci/verify-local-docker');

  assert.match(verifier, /backend\/gradlew -p backend test/);
  assert.match(verifier, /backend\/gradlew -p backend lambdaZip/);
  assert.match(verifier, /flutter analyze --no-fatal-warnings --no-fatal-infos/);
  assert.match(verifier, /backend\/lambda\/build\.sh --check/);
  assert.match(verifier, /terraform (init|validate)/);
  assert.match(verifier, /e2e_playwright_test\.js/);
  assert.doesNotMatch(verifier, /CODEBUILD_|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN/);
  assert.doesNotMatch(dockerVerifier, /CODEBUILD_|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN/);
});

test('hosted validation entry points are retired', () => {
  const retiredPaths = [
    'buildspec.yml',
    '.github/workflows/ci.yml',
    '.github/workflows/production-deploy.yml',
    '.github/workflows/verify-dynamodb-restore.yml',
    'scripts/ci/verify',
  ];

  for (const relativePath of retiredPaths) {
    assert.equal(
      fs.existsSync(path.join(root, relativePath)),
      false,
      `${relativePath} must not remain an active hosted validation entry point`,
    );
  }
});
