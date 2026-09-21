const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
const verifier = path.join(root, 'scripts', 'ci', 'verify-local-docker');

test('local verification exposes a safe, reproducible Docker contract', () => {
  const result = spawnSync(verifier, ['--print-config'], {
    cwd: root,
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Dockerfile: ci\/local-verification\/Dockerfile/);
  assert.match(result.stdout, /AWS credential injection: disabled/);
  assert.match(result.stdout, /Terraform mutation: validation only/);
  assert.match(result.stdout, /Docker group recovery: automatic/);
});

test('local verification pins the canonical toolchain', () => {
  const dockerfile = fs.readFileSync(
    path.join(root, 'ci', 'local-verification', 'Dockerfile'),
    'utf8',
  );

  assert.match(dockerfile, /JAVA_VERSION=21/);
  assert.match(dockerfile, /NODE_VERSION=20\.20\.2/);
  assert.match(dockerfile, /FLUTTER_VERSION=3\.44\.0/);
  assert.match(dockerfile, /TERRAFORM_VERSION=1\.5\.7/);
  assert.match(dockerfile, /PLAYWRIGHT_VERSION=1\.47\.2/);
  assert.match(dockerfile, /chmod -R a\+rwX .*\/opt\/flutter\/packages\/flutter_tools/);
  assert.match(dockerfile, /chmod -R a\+rwX .*\/opt\/flutter\/bin\/cache/);
});

test('local Docker verification delegates to every local validation lane', () => {
  const wrapper = fs.readFileSync(verifier, 'utf8');
  const hostedVerifier = fs.readFileSync(
    path.join(root, 'scripts', 'ci', 'verify-local'),
    'utf8',
  );

  assert.match(wrapper, /exec \.\/scripts\/ci\/verify-local\b/);
  assert.match(wrapper, /--env AWS_ACCESS_KEY_ID=/);
  assert.match(wrapper, /--env AWS_SECRET_ACCESS_KEY=/);
  assert.match(wrapper, /--env AWS_SESSION_TOKEN=/);
  assert.match(wrapper, /--env AWS_SHARED_CREDENTIALS_FILE=\/dev\/null/);
  assert.match(wrapper, /--env AWS_EC2_METADATA_DISABLED=true/);
  assert.match(hostedVerifier, /backend\/gradlew -p backend test/);
  assert.match(hostedVerifier, /backend\/gradlew -p backend lambdaZip/);
  assert.match(hostedVerifier, /backend\/lambda\/build\.sh --check/);
  assert.match(hostedVerifier, /node --test backend\/lambda\/test\/\*\.test\.js/);
  assert.match(hostedVerifier, /terraform .*init -backend=false/);
  assert.match(hostedVerifier, /terraform .*validate/);
  assert.match(hostedVerifier, /flutter analyze/);
  assert.match(hostedVerifier, /flutter test/);
  assert.match(hostedVerifier, /flutter build web/);
  assert.match(hostedVerifier, /e2e_playwright_test\.js/);
  assert.match(hostedVerifier, /bash scripts\/test_production_deploy_guard\.sh/);
  assert.match(hostedVerifier, /require\.resolve\('playwright'\)/);
  assert.match(hostedVerifier, /npm install --no-save --no-package-lock playwright@1\.47\.2/);
  assert.doesNotMatch(wrapper, /terraform apply|aws s3 (cp|sync)|aws lambda update-function-code/);
});

test('browser verification reuses the image-provided Playwright browser', () => {
  const hostedVerifier = fs.readFileSync(
    path.join(root, 'scripts', 'ci', 'verify-local'),
    'utf8',
  );

  const managedBrowserLookup = hostedVerifier.indexOf('chromium.executablePath()');
  const browserInstallFallback = hostedVerifier.indexOf(
    'playwright install --with-deps chromium',
  );

  assert.ok(managedBrowserLookup >= 0);
  assert.ok(browserInstallFallback >= 0);
  assert.ok(
    managedBrowserLookup < browserInstallFallback,
    'the managed Playwright browser must be checked before installing dependencies',
  );
});

test('validation builds the ignored Lambda archive before checking parity', () => {
  const hostedVerifier = fs.readFileSync(
    path.join(root, 'scripts', 'ci', 'verify-local'),
    'utf8',
  );
  const buildArchive = hostedVerifier.indexOf('backend/lambda/build.sh\n');
  const checkArchive = hostedVerifier.indexOf('backend/lambda/build.sh --check');

  assert.ok(buildArchive >= 0);
  assert.ok(checkArchive >= 0);
  assert.ok(
    buildArchive < checkArchive,
    'the ignored Lambda archive must be built before its parity check',
  );
});

test('local Docker verification preserves Git worktree metadata in the container', () => {
  const wrapper = fs.readFileSync(verifier, 'utf8');
  const result = spawnSync(verifier, ['--print-config'], {
    cwd: root,
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Git directory:/);
  assert.match(result.stdout, /Git common directory:/);
  assert.match(wrapper, /rev-parse --absolute-git-dir/);
  assert.match(wrapper, /rev-parse --path-format=absolute --git-common-dir/);
  assert.match(wrapper, /--volume "\$GIT_COMMON_DIR:\$GIT_COMMON_DIR:ro"/);
  assert.doesNotMatch(wrapper, /--env GIT_DIR=/);
  assert.doesNotMatch(wrapper, /--env GIT_WORK_TREE=/);
});

test('local Docker verification recovers a stale Docker supplementary group', () => {
  const wrapper = fs.readFileSync(verifier, 'utf8');

  assert.match(wrapper, /LOCAL_VERIFIER_DOCKER_GROUP_REEXEC/);
  assert.match(wrapper, /id -nG "\$\(id -un\)"/);
  assert.match(wrapper, /sg docker -c/);
  assert.match(wrapper, /printf -v quoted_arg '%q'/);
  assert.match(wrapper, /exec sg docker -c/);
});

test('the runbook records the D1 parity boundary and failure behavior', () => {
  const runbook = fs.readFileSync(
    path.join(root, 'docs', 'operations', 'local-verification.md'),
    'utf8',
  );

  assert.match(runbook, /D1 hosted baseline/);
  assert.match(runbook, /post-merge release/);
  assert.match(runbook, /D3/);
  assert.match(runbook, /DynamoDB local/);
  assert.match(runbook, /AWS credential/);
  assert.match(runbook, /Git worktree/);
  assert.match(runbook, /common directory/);
  assert.match(runbook, /non-zero/);
});
