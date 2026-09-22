const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

test('local verification is independent of hosted CI and AWS credentials', () => {
  const verifier = read('scripts/ci/verify-local');
  const dockerRunner = read('scripts/ci/verify-local-docker');
  const dockerfile = read('ci/local-verification/Dockerfile');

  assert.match(verifier, /backend\/gradlew -p backend test/);
  assert.match(verifier, /backend\/gradlew -p backend lambdaZip/);
  assert.match(verifier, /backend\/lambda\/build\.sh --check/);
  assert.match(verifier, /terraform -chdir=terraform validate/);
  assert.match(verifier, /flutter test/);
  assert.match(verifier, /e2e_playwright_test\.js/);
  assert.doesNotMatch(verifier, /CODEBUILD_|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN/);
  assert.doesNotMatch(verifier, /AWS validation gates/);

  assert.match(dockerRunner, /build_args=\(build/);
  assert.match(dockerRunner, /docker run/);
  assert.match(dockerRunner, /sg docker/);
  assert.match(dockerRunner, /ci\/local-verification\/Dockerfile/);
  assert.match(dockerRunner, /scripts\/ci\/verify-local/);
  assert.match(dockerRunner, /--log-file/);
  assert.match(dockerRunner, /--env AWS_ACCESS_KEY_ID=/);
  assert.match(dockerRunner, /--env AWS_CONFIG_FILE=\/dev\/null/);
  assert.match(dockerRunner, /--tmpfs \/tmp:exec/);
  assert.doesNotMatch(dockerRunner, /CODEBUILD_/);
  assert.doesNotMatch(dockerRunner, /terraform apply|aws s3 (cp|sync)|aws lambda update-function-code/);

  assert.match(dockerfile, /JAVA_VERSION=21/);
  assert.match(dockerfile, /FLUTTER_VERSION=3\.44\.0/);
  assert.match(dockerfile, /chmod -R a\+rwX .*\/opt\/flutter\/packages\/flutter_tools/);
  assert.match(dockerfile, /chmod -R a\+rwX .*\/opt\/flutter\/bin\/cache/);
});

test('hosted validation entry points are retired', () => {
  const retiredPaths = [
    'buildspec.yml',
    '.github/workflows/ci.yml',
    '.github/workflows/production-deploy.yml',
    '.github/workflows/verify-dynamodb-restore.yml',
    'scripts/ci/verify',
    'ci/local-toolchain/Dockerfile',
  ];

  for (const relativePath of retiredPaths) {
    assert.equal(
      fs.existsSync(path.join(root, relativePath)),
      false,
      `${relativePath} must not remain an active hosted or duplicate validation entry point`,
    );
  }
});
