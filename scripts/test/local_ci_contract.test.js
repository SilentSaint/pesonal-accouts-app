const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

test('dependency retry helper retries transient commands with bounded backoff', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'local-verifier-retry-'));
  const stateFile = path.join(tempRoot, 'attempts');
  const command = path.join(tempRoot, 'transient-command');
  fs.writeFileSync(
    command,
    '#!/usr/bin/env bash\ncount=0\n[[ -f "$1" ]] && count=$(<"$1")\ncount=$((count + 1))\nprintf "%s" "$count" > "$1"\n((count >= 3))\n',
  );
  fs.chmodSync(command, 0o755);

  try {
    const result = spawnSync(
      path.join(root, 'scripts', 'ci', 'retry-command'),
      ['Transient dependency', command, stateFile],
      {
        cwd: root,
        encoding: 'utf8',
        env: {
          ...process.env,
          LOCAL_VERIFIER_RETRY_ATTEMPTS: '3',
          LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '0',
        },
      },
    );

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /attempt 1\/3/);
    assert.match(result.stderr, /attempt 2\/3/);
    assert.equal(fs.readFileSync(stateFile, 'utf8'), '3');
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('dependency retry helper rejects retry counts outside its safe bound', () => {
  const result = spawnSync(
    path.join(root, 'scripts', 'ci', 'retry-command'),
    ['Overflowing retry', 'true'],
    {
      cwd: root,
      encoding: 'utf8',
      env: {
        ...process.env,
        LOCAL_VERIFIER_RETRY_ATTEMPTS: '9223372036854775808',
        LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '0',
      },
    },
  );

  assert.equal(result.status, 64, result.stderr);
  assert.match(result.stderr, /LOCAL_VERIFIER_RETRY_ATTEMPTS must be between 1 and 10/);
});

test('dependency retry helper normalizes zero-padded retry counts as decimal', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'local-verifier-padded-attempts-'));
  const stateFile = path.join(tempRoot, 'attempts');
  const command = path.join(tempRoot, 'transient-command');
  fs.writeFileSync(
    command,
    '#!/usr/bin/env bash\ncount=0\n[[ -f "$1" ]] && count=$(<"$1")\ncount=$((count + 1))\nprintf "%s" "$count" > "$1"\n((count >= 8))\n',
  );
  fs.chmodSync(command, 0o755);

  try {
    const result = spawnSync(
      path.join(root, 'scripts', 'ci', 'retry-command'),
      ['Zero-padded retry count', command, stateFile],
      {
        cwd: root,
        encoding: 'utf8',
        env: {
          ...process.env,
          LOCAL_VERIFIER_RETRY_ATTEMPTS: '08',
          LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '0',
        },
      },
    );

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /attempt 7\/8/);
    assert.equal(fs.readFileSync(stateFile, 'utf8'), '8');
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('dependency retry helper normalizes decimal delays and bounds backoff', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'local-verifier-delay-'));
  const stateFile = path.join(tempRoot, 'attempts');
  const command = path.join(tempRoot, 'transient-command');
  const fakeSleep = path.join(tempRoot, 'sleep');
  fs.writeFileSync(
    command,
    '#!/usr/bin/env bash\ncount=0\n[[ -f "$1" ]] && count=$(<"$1")\ncount=$((count + 1))\nprintf "%s" "$count" > "$1"\n((count >= 2))\n',
  );
  fs.writeFileSync(fakeSleep, '#!/usr/bin/env bash\nexit 0\n');
  fs.chmodSync(command, 0o755);
  fs.chmodSync(fakeSleep, 0o755);

  try {
    const result = spawnSync(
      path.join(root, 'scripts', 'ci', 'retry-command'),
      ['Padded delay', command, stateFile],
      {
        cwd: root,
        encoding: 'utf8',
        env: {
          ...process.env,
          LOCAL_VERIFIER_RETRY_ATTEMPTS: '2',
          LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '08',
          PATH: `${tempRoot}:${process.env.PATH}`,
        },
      },
    );

    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(stateFile, 'utf8'), '2');

    const tooLarge = spawnSync(
      path.join(root, 'scripts', 'ci', 'retry-command'),
      ['Oversized delay', 'true'],
      {
        cwd: root,
        encoding: 'utf8',
        env: {
          ...process.env,
          LOCAL_VERIFIER_RETRY_ATTEMPTS: '2',
          LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '922337203685477581',
        },
      },
    );

    assert.equal(tooLarge.status, 64, tooLarge.stderr);
    assert.match(tooLarge.stderr, /LOCAL_VERIFIER_RETRY_DELAY_SECONDS must be between 0 and 922337203685477580/);

    const oversizedLexicallySmall = spawnSync(
      path.join(root, 'scripts', 'ci', 'retry-command'),
      ['Overflowing delay', 'true'],
      {
        cwd: root,
        encoding: 'utf8',
        env: {
          ...process.env,
          LOCAL_VERIFIER_RETRY_ATTEMPTS: '10',
          LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '2000000000000000000',
        },
      },
    );

    assert.equal(oversizedLexicallySmall.status, 64, oversizedLexicallySmall.stderr);
    assert.match(oversizedLexicallySmall.stderr, /LOCAL_VERIFIER_RETRY_DELAY_SECONDS must be between 0 and 922337203685477580/);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('local verification is independent of hosted CI and AWS credentials', () => {
  const verifier = read('scripts/ci/verify-local');
  const dockerRunner = read('scripts/ci/verify-local-docker');
  const dockerfile = read('ci/local-verification/Dockerfile');

  assert.match(verifier, /backend\/gradlew -p backend test/);
  assert.match(verifier, /backend\/gradlew -p backend lambdaZip/);
  assert.match(verifier, /scripts\/ci\/retry-command "Gradle dependency resolution" \.\/backend\/gradlew -p backend testClasses --no-daemon/);
  assert.match(verifier, /scripts\/ci\/retry-command "Gradle test runtime dependency resolution" \.\/backend\/gradlew -p backend test --test-dry-run --no-daemon/);
  assert.match(verifier, /scripts\/ci\/retry-command "Gradle test runtime dependency resolution" \.\/backend\/gradlew -p backend test --test-dry-run --no-daemon/);
  assert.match(verifier, /backend\/lambda\/build\.sh --check/);
  assert.match(verifier, /terraform -chdir=terraform validate/);
  assert.match(verifier, /flutter test/);
  assert.match(verifier, /e2e_playwright_test\.js/);
  assert.doesNotMatch(verifier, /CODEBUILD_|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN/);
  assert.doesNotMatch(verifier, /AWS validation gates/);

  assert.match(dockerRunner, /build_args=\(build/);
  assert.match(dockerRunner, /"\$DOCKER_BIN" run/);
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
    '.github/workflows/pull-request.yml',
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

test('developer build instructions use the local verifier', () => {
  const agents = read('AGENTS.md');
  const workflow = read('docs/engineering/workflow.md');
  const verifierContract = read('scripts/ci/test-verify-contract.sh');
  const deletedVerifierReference = /scripts\/ci\/verify(?:[^-A-Za-z]|$)/;

  assert.match(agents, /scripts\/ci\/verify-local-docker/);
  assert.doesNotMatch(agents, /allow\s+CodeBuild\s+to\s+validate/);
  assert.doesNotMatch(agents, deletedVerifierReference);

  assert.match(workflow, /scripts\/ci\/verify-local-docker/);
  assert.doesNotMatch(workflow, deletedVerifierReference);

  assert.match(verifierContract, /scripts\/ci\/verify-local\b/);
  assert.doesNotMatch(verifierContract, deletedVerifierReference);
});

test('Codex PR review automation stays bound to the authorized current head', () => {
  const agents = read('AGENTS.md');
  const workflow = read('docs/engineering/workflow.md');

  assert.match(workflow, /arm a quiet Codex heartbeat automation in that\s+same task/);
  assert.match(workflow, /exact (?:current )?head SHA/);
  assert.match(
    workflow,
    /After each fix commit,\s*refresh the\s+tracked SHA and invalidate prior approvals\./,
  );
  assert.match(workflow, /local `code-review`\s+skill on the PR diff/);
  assert.match(workflow, /Standards and Spec agents review in parallel/);
  assert.ok(
    workflow.includes("`Codex Review: Didn't find any major issues. Keep it up!`"),
    'the exact Codex review authorization message must be preserved',
  );
  assert.match(workflow, /valid current-head Codex approval/);
  assert.match(workflow, /no actionable\s+review conversations remain unresolved/);
  assert.match(workflow, /exact-head\s+local Docker gate passes/);
  assert.match(workflow, /Merge through the pull-request path only; never write directly to\s+`main`/);
  assert.match(
    agents,
    /Agents may merge only when the canonical engineering\s+workflow authorizes it and its gates pass\./,
  );
});
