const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');

test('local verification is independent of hosted CI and AWS credentials', () => {
  const verifier = fs.readFileSync(path.join(root, 'scripts/ci/verify-local'), 'utf8');
  const dockerRunner = fs.readFileSync(
    path.join(root, 'scripts/ci/verify-local-docker'),
    'utf8',
  );
  const dockerfile = fs.readFileSync(
    path.join(root, 'ci/local-toolchain/Dockerfile'),
    'utf8',
  );

  assert.match(verifier, /backend\/gradlew -p backend test/);
  assert.match(verifier, /backend\/lambda\/build\.sh --check/);
  assert.match(verifier, /terraform -chdir=terraform validate/);
  assert.match(verifier, /flutter test/);
  assert.match(verifier, /e2e_playwright_test\.js/);
  assert.doesNotMatch(verifier, /CODEBUILD_|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY/);
  assert.doesNotMatch(verifier, /AWS validation gates/);

  assert.match(dockerRunner, /docker build/);
  assert.match(dockerRunner, /docker run/);
  assert.match(dockerRunner, /sg docker/);
  assert.match(dockerRunner, /ci\/local-toolchain\/Dockerfile/);
  assert.match(dockerRunner, /scripts\/ci\/verify-local/);
  assert.match(dockerRunner, /--log-file/);
  assert.doesNotMatch(dockerRunner, /CODEBUILD_|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY/);
  assert.match(dockerfile, /chmod -R a\+rwX \/opt\/flutter \/opt\/terraform \/opt\/ms-playwright/);
});
