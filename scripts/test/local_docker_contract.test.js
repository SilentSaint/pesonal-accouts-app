const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
const verifier = path.join(root, 'scripts', 'ci', 'verify-local-docker');

function runWithFakeDocker(
  fakeDockerContents,
  args,
  envOverrides = {},
  fakeGitContents = null,
  fakeMkdirContents = null,
) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'local-verifier-contract-'));
  const fakeDocker = path.join(tempRoot, 'docker');
  const fakeCurl = path.join(tempRoot, 'curl');
  const fakeGit = path.join(tempRoot, 'git');
  const fakeMkdir = path.join(tempRoot, 'mkdir');
  const cacheDir = path.join(tempRoot, 'cache');
  fs.mkdirSync(cacheDir);
  fs.writeFileSync(fakeDocker, `#!/usr/bin/env bash\n${fakeDockerContents}\n`);
  fs.writeFileSync(
    fakeGit,
    fakeGitContents ??
      '#!/usr/bin/env bash\nfor arg in "$@"; do\n  [[ "$arg" == diff || "$arg" == status ]] && exit 0\ndone\nexec /usr/bin/git "$@"\n',
  );
  fs.chmodSync(fakeDocker, 0o755);
  fs.writeFileSync(
    fakeCurl,
    [
      '#!/usr/bin/env bash',
      'if [[ -n "$LOCAL_VERIFIER_TEST_UNREACHABLE_ENDPOINT" ]]; then',
      '  for arg in "$@"; do',
      '    [[ "$arg" == *"$LOCAL_VERIFIER_TEST_UNREACHABLE_ENDPOINT"* ]] && exit 7',
      '  done',
      'fi',
      'exit 0',
    ].join('\n'),
  );
  fs.chmodSync(fakeCurl, 0o755);
  fs.chmodSync(fakeGit, 0o755);
  if (fakeMkdirContents !== null) {
    fs.writeFileSync(fakeMkdir, fakeMkdirContents);
    fs.chmodSync(fakeMkdir, 0o755);
  }

  try {
    const resolvedArgs = args.map((arg) => (
      arg === '__CACHE_DIR__' ? cacheDir : arg
    ));
    return spawnSync(verifier, resolvedArgs, {
      cwd: root,
      encoding: 'utf8',
      env: {
        ...process.env,
        AWS_ACCESS_KEY_ID: '',
        AWS_SECRET_ACCESS_KEY: '',
        AWS_SESSION_TOKEN: '',
        AWS_SECURITY_TOKEN: '',
        AWS_PROFILE: '',
        AWS_CONFIG_FILE: '/dev/null',
        AWS_SHARED_CREDENTIALS_FILE: '/dev/null',
        AWS_EC2_METADATA_DISABLED: 'true',
        LOCAL_VERIFIER_MIN_CACHE_FREE_MB: '1',
        LOCAL_VERIFIER_DOCKER_BIN: fakeDocker,
        LOCAL_VERIFIER_DOCKER_GROUP_REEXEC: '1',
        LOCAL_VERIFIER_TEST_CACHE_DIR: cacheDir,
        PATH: `${tempRoot}:${process.env.PATH}`,
        ...envOverrides,
      },
    });
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

test('local verification exposes a safe, reproducible Docker contract', () => {
  const wrapper = fs.readFileSync(verifier, 'utf8');
  const dockerfile = fs.readFileSync(
    path.join(root, 'ci', 'local-verification', 'Dockerfile'),
    'utf8',
  );
  const result = spawnSync(verifier, ['--print-config'], {
    cwd: root,
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Dockerfile: ci\/local-verification\/Dockerfile/);
  assert.match(result.stdout, /AWS credential injection: disabled/);
  assert.match(
    result.stdout,
    /AWS IMDS credential lookup: disabled \(no network-level block\)/,
  );
  assert.match(result.stdout, /Terraform mutation: validation only/);
  assert.match(result.stdout, /Docker access: preflighted/);
  assert.match(result.stdout, /Verification source: detached worktree snapshot of HEAD/);
  assert.match(dockerfile, /PLAYWRIGHT_VERSION=1\.47\.2/);
  assert.match(wrapper, /playwright\.azureedge\.net\/builds\/chromium\/1134\/chromium-linux\.zip/);
});

test('preflight accepts a persistent cache directory and checks Docker before the gate', () => {
  const result = runWithFakeDocker('exit 0', [
    '--preflight-only',
    '--cache-dir',
    '__CACHE_DIR__',
  ]);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Docker preflight passed/);
  assert.match(result.stdout, /Cache directory:/);
});

test('Docker gate uses immutable source and helper snapshots when checkout changes during image build', () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'local-verifier-snapshot-'));
  const checkout = path.join(tempRoot, 'checkout');
  const cacheDir = path.join(tempRoot, 'cache');
  const fakeDocker = path.join(tempRoot, 'docker');
  const fakeCurl = path.join(tempRoot, 'curl');
  const fakeId = path.join(tempRoot, 'id');
  const buildCountFile = path.join(tempRoot, 'build-attempts');
  const idMarker = path.join(tempRoot, 'id-marker');
  const trackedFiles = [
    'scripts/ci/verify-local-docker',
    'scripts/ci/retry-command',
    'ci/local-verification/Dockerfile',
  ];

  try {
    for (const relativePath of trackedFiles) {
      const destination = path.join(checkout, relativePath);
      fs.mkdirSync(path.dirname(destination), { recursive: true });
      fs.copyFileSync(path.join(root, relativePath), destination);
    }
    fs.writeFileSync(path.join(checkout, 'revision.txt'), 'original committed source\n');
    fs.mkdirSync(cacheDir);
    fs.writeFileSync(fakeCurl, '#!/usr/bin/env bash\nexit 0\n');
    fs.chmodSync(fakeCurl, 0o755);

    for (const args of [
      ['init', '--quiet', checkout],
      ['-C', checkout, 'config', 'user.name', 'Local verifier contract'],
      ['-C', checkout, 'config', 'user.email', 'local-verifier@example.invalid'],
      ['-C', checkout, 'add', '--', '.'],
      ['-C', checkout, 'commit', '--quiet', '-m', 'snapshot fixture'],
    ]) {
      const result = spawnSync('git', args, { encoding: 'utf8' });
      assert.equal(result.status, 0, result.stderr);
    }

    fs.writeFileSync(
      fakeDocker,
      [
        '#!/usr/bin/env bash',
        'set -u',
        'if [[ "$1" == "info" ]]; then exit 0; fi',
        'if [[ "$1" == "build" ]]; then',
        '  count=0',
        '  [[ -f "$LOCAL_VERIFIER_TEST_BUILD_COUNT" ]] && count=$(<"$LOCAL_VERIFIER_TEST_BUILD_COUNT")',
        '  count=$((count + 1))',
        '  printf "%s" "$count" > "$LOCAL_VERIFIER_TEST_BUILD_COUNT"',
        '  printf "changed during image build\\n" > "$LOCAL_VERIFIER_TEST_CHECKOUT/revision.txt"',
        '  if ((count < 2)); then exit 1; fi',
        '  exit 0',
        'fi',
        'if [[ "$1" == "run" ]]; then',
        '  workspace_source=""',
        '  while (($#)); do',
        '    if [[ "$1" == "--volume" ]]; then',
        '      case "$2" in',
        '        *:/workspace) workspace_source="${2%:/workspace}" ;;',
        '      esac',
        '      shift 2',
        '    else',
        '      shift',
        '    fi',
        '  done',
        '  [[ -n "$workspace_source" ]] || { echo "workspace mount missing" >&2; exit 23; }',
        '  [[ "$workspace_source" != "$LOCAL_VERIFIER_TEST_CHECKOUT" ]] || { echo "live checkout was mounted" >&2; exit 24; }',
        '  [[ "$(cat "$workspace_source/revision.txt")" == "original committed source" ]] || { echo "snapshot content changed" >&2; exit 25; }',
        '  exit 0',
        'fi',
        'exit 0',
      ].join('\n'),
    );
    fs.chmodSync(fakeDocker, 0o755);
    fs.writeFileSync(
      fakeId,
      [
        '#!/usr/bin/env bash',
        'if [[ ! -e "$LOCAL_VERIFIER_TEST_ID_MARKER" ]]; then',
        '  : > "$LOCAL_VERIFIER_TEST_ID_MARKER"',
        '  printf "#!/usr/bin/env bash\\necho live checkout retry helper executed >&2\\nexit 77\\n" > "$LOCAL_VERIFIER_TEST_CHECKOUT/scripts/ci/retry-command"',
        'fi',
        'exec /usr/bin/id "$@"',
      ].join('\n'),
    );
    fs.chmodSync(fakeId, 0o755);

    const result = spawnSync(
      path.join(checkout, 'scripts', 'ci', 'verify-local-docker'),
      ['--cache-dir', cacheDir],
      {
        cwd: checkout,
        encoding: 'utf8',
        env: {
          ...process.env,
          AWS_ACCESS_KEY_ID: '',
          AWS_SECRET_ACCESS_KEY: '',
          AWS_SESSION_TOKEN: '',
          AWS_SECURITY_TOKEN: '',
          AWS_PROFILE: '',
          AWS_CONFIG_FILE: '/dev/null',
          AWS_SHARED_CREDENTIALS_FILE: '/dev/null',
          AWS_EC2_METADATA_DISABLED: 'true',
          LOCAL_VERIFIER_MIN_CACHE_FREE_MB: '1',
          LOCAL_VERIFIER_DOCKER_BIN: fakeDocker,
          LOCAL_VERIFIER_DOCKER_GROUP_REEXEC: '1',
          LOCAL_VERIFIER_RETRY_ATTEMPTS: '2',
          LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '0',
          LOCAL_VERIFIER_TEST_CHECKOUT: checkout,
          LOCAL_VERIFIER_TEST_BUILD_COUNT: buildCountFile,
          LOCAL_VERIFIER_TEST_ID_MARKER: idMarker,
          PATH: `${tempRoot}:${process.env.PATH}`,
        },
      },
    );

    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(buildCountFile, 'utf8'), '2');
    assert.match(result.stderr, /retrying in 0s/);
    assert.equal(fs.readFileSync(path.join(checkout, 'revision.txt'), 'utf8'), 'changed during image build\n');
    assert.deepEqual(fs.readdirSync(path.join(cacheDir, 'worktrees')), []);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('dependency network outage fails preflight before image build with actionable guidance', () => {
  const result = runWithFakeDocker(
    'if [[ "$1" == "info" ]]; then exit 0; fi\necho "docker image build started" >&2\nexit 91',
    ['--cache-dir', '__CACHE_DIR__'],
    {
      LOCAL_VERIFIER_TEST_UNREACHABLE_ENDPOINT: 'services.gradle.org',
      LOCAL_VERIFIER_RETRY_ATTEMPTS: '1',
      LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '0',
    },
  );

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Dependency network preflight failed.*services\.gradle\.org/s);
  assert.match(result.stderr, /outbound HTTPS/i);
  assert.doesNotMatch(result.stderr, /docker image build started/);
});

test('cold Docker image toolchain host outage fails preflight before image build', () => {
  const result = runWithFakeDocker(
    'if [[ "$1" == "info" ]]; then exit 0; fi\necho "docker image build started" >&2\nexit 91',
    ['--cache-dir', '__CACHE_DIR__'],
    {
      LOCAL_VERIFIER_TEST_UNREACHABLE_ENDPOINT: 'nodejs.org',
      LOCAL_VERIFIER_RETRY_ATTEMPTS: '1',
      LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '0',
    },
  );

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Dependency network preflight failed.*nodejs\.org/s);
  assert.doesNotMatch(result.stderr, /docker image build started/);
});

test('Playwright CDN preflight accepts a mirror fallback and rejects a total outage', () => {
  const fakeDocker = 'if [[ "$1" == "info" ]]; then exit 0; fi\necho "docker was unexpectedly reached" >&2\nexit 91';
  const args = ['--preflight-only', '--cache-dir', '__CACHE_DIR__'];
  const env = {
    LOCAL_VERIFIER_RETRY_ATTEMPTS: '1',
    LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '0',
  };
  const fallback = runWithFakeDocker(fakeDocker, args, {
    ...env,
    LOCAL_VERIFIER_TEST_UNREACHABLE_ENDPOINT: 'playwright.azureedge.net',
  });
  const outage = runWithFakeDocker(fakeDocker, args, {
    ...env,
    LOCAL_VERIFIER_TEST_UNREACHABLE_ENDPOINT: 'playwright',
  });

  assert.equal(fallback.status, 0, fallback.stderr);
  assert.match(fallback.stdout, /Playwright browser CDN preflight passed/);
  assert.notEqual(outage.status, 0);
  assert.match(outage.stderr, /unable to reach any Playwright Chromium CDN/);
  assert.doesNotMatch(outage.stderr, /docker was unexpectedly reached/);
});

test('preflight creates every mounted cache directory and Terraform lock before Docker access', () => {
  const result = runWithFakeDocker(
    'for cache_path in gradle terraform/plugin-cache flutter/pub-cache npm; do\n  [[ -d "$LOCAL_VERIFIER_TEST_CACHE_DIR/$cache_path" ]] || exit 9\ndone\n[[ -f "$LOCAL_VERIFIER_TEST_CACHE_DIR/terraform/plugin-cache.lock" && -w "$LOCAL_VERIFIER_TEST_CACHE_DIR/terraform/plugin-cache.lock" ]] || exit 10\nexit 0',
    ['--preflight-only', '--cache-dir', '__CACHE_DIR__'],
  );

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Docker access preflight passed/);
});

test('preflight checks mounted cache subdirectories before Docker starts', () => {
  const result = runWithFakeDocker(
    'echo docker should not run >&2; exit 0',
    ['--preflight-only', '--cache-dir', '__CACHE_DIR__'],
    {},
    null,
    '#!/usr/bin/env bash\nfor arg in "$@"; do\n  [[ "$arg" == */gradle ]] && { echo "simulated cache permission failure" >&2; exit 1; }\ndone\nexec /usr/bin/mkdir "$@"\n',
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /cache.*not writable|unable to create.*cache/i);
  assert.doesNotMatch(result.stderr, /Docker access preflight passed/);
});

test('Docker access failures stop before an image build with actionable output', () => {
  const result = runWithFakeDocker('exit 1', [
    '--preflight-only',
    '--cache-dir',
    '__CACHE_DIR__',
  ]);

  assert.equal(result.status, 126);
  assert.match(result.stderr, /Docker access preflight failed/);
  assert.match(result.stderr, /docker group|Docker daemon|permission/i);
});

test('insufficient cache space stops before Docker starts', () => {
  const result = runWithFakeDocker(
    'exit 0',
    ['--preflight-only', '--cache-dir', '__CACHE_DIR__'],
    { LOCAL_VERIFIER_MIN_CACHE_FREE_MB: '999999999' },
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /cache has only .* required before starting/i);
});

test('oversized cache thresholds are rejected before arithmetic', () => {
  const result = runWithFakeDocker(
    'echo docker should not run >&2; exit 0',
    ['--preflight-only', '--cache-dir', '__CACHE_DIR__'],
    { LOCAL_VERIFIER_MIN_CACHE_FREE_MB: '9223372036854775808' },
  );

  assert.equal(result.status, 64);
  assert.match(result.stderr, /LOCAL_VERIFIER_MIN_CACHE_FREE_MB must be between 0 and 9223372036854775807/);
  assert.doesNotMatch(result.stderr, /Docker access preflight passed/);
});

test('oversized cache thresholds that wrap negative are rejected', () => {
  const result = runWithFakeDocker(
    'echo docker should not run >&2; exit 0',
    ['--preflight-only', '--cache-dir', '__CACHE_DIR__'],
    { LOCAL_VERIFIER_MIN_CACHE_FREE_MB: '10000000000000000000' },
  );

  assert.equal(result.status, 64);
  assert.match(result.stderr, /LOCAL_VERIFIER_MIN_CACHE_FREE_MB must be between 0 and 9223372036854775807/);
  assert.doesNotMatch(result.stderr, /Docker access preflight passed/);
});

test('zero-padded cache thresholds are parsed as decimal', () => {
  const result = runWithFakeDocker(
    'echo docker should not run >&2; exit 0',
    ['--preflight-only', '--cache-dir', '__CACHE_DIR__'],
    { LOCAL_VERIFIER_MIN_CACHE_FREE_MB: '0999999999' },
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /cache has only .* required before starting/i);
  assert.doesNotMatch(result.stderr, /Docker access preflight passed/);
});

test('retry attempts above the helper limit stop preflight before Docker starts', () => {
  const result = runWithFakeDocker(
    'echo docker should not run >&2; exit 0',
    ['--preflight-only', '--cache-dir', '__CACHE_DIR__'],
    {
      LOCAL_VERIFIER_RETRY_ATTEMPTS: '11',
      LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '0',
    },
  );

  assert.equal(result.status, 64);
  assert.match(result.stderr, /LOCAL_VERIFIER_RETRY_ATTEMPTS must be between 1 and 10/);
  assert.doesNotMatch(result.stderr, /Docker access preflight passed/);
});

test('zero-padded retry attempts pass Docker preflight as decimal values', () => {
  const result = runWithFakeDocker(
    'exit 0',
    ['--preflight-only', '--cache-dir', '__CACHE_DIR__'],
    {
      LOCAL_VERIFIER_RETRY_ATTEMPTS: '08',
      LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '0',
    },
  );

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Docker preflight passed/);
});

test('retry delays above the helper limit stop preflight before Docker starts', () => {
  const result = runWithFakeDocker(
    'echo docker should not run >&2; exit 0',
    ['--preflight-only', '--cache-dir', '__CACHE_DIR__'],
    {
      LOCAL_VERIFIER_RETRY_ATTEMPTS: '10',
      LOCAL_VERIFIER_RETRY_DELAY_SECONDS: '2000000000000000000',
    },
  );

  assert.equal(result.status, 64);
  assert.match(result.stderr, /LOCAL_VERIFIER_RETRY_DELAY_SECONDS must be between 0 and 922337203685477580/);
  assert.doesNotMatch(result.stderr, /Docker access preflight passed/);
});

test('log files inside the checkout are rejected before they are opened', () => {
  const logFile = path.join(root, '.local-verifier-contract.log');

  try {
    const result = runWithFakeDocker(
      'echo docker should not run >&2; exit 0',
      ['--preflight-only', '--cache-dir', '__CACHE_DIR__', '--log-file', logFile],
    );

    assert.equal(result.status, 1);
    assert.match(result.stderr, /log.*outside.*checkout|checkout.*log/i);
    assert.equal(fs.existsSync(logFile), false);
  } finally {
    fs.rmSync(logFile, { force: true });
  }
});

test('non-ignored untracked files stop preflight before Docker starts', () => {
  const result = runWithFakeDocker(
    'echo docker should not run >&2; exit 0',
    ['--preflight-only', '--cache-dir', '__CACHE_DIR__'],
    {},
    '#!/usr/bin/env bash\nfor arg in "$@"; do\n  [[ "$arg" == status ]] && { printf "?? untracked.tf\\n"; exit 0; }\n  [[ "$arg" == diff ]] && exit 0\ndone\nexec /usr/bin/git "$@"\n',
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /tracked changes or non-ignored untracked files|clean checkout/i);
  assert.doesNotMatch(result.stderr, /Docker access preflight passed/);
});

test('cache directories inside the checkout are rejected before Docker starts', () => {
  const cacheDir = path.join(root, '.local-verifier-contract-cache');

  try {
    const result = runWithFakeDocker(
      'echo docker should not run >&2; exit 0',
      ['--preflight-only', '--cache-dir', cacheDir],
    );

    assert.equal(result.status, 1);
    assert.match(result.stderr, /cache.*outside.*checkout|checkout.*cache/i);
  } finally {
    fs.rmSync(cacheDir, { recursive: true, force: true });
  }
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
  assert.match(dockerfile, /util-linux/);
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
  assert.match(wrapper, /TF_DATA_DIR=\/tmp\/aet-terraform-data/);
  assert.match(wrapper, /TF_PLUGIN_CACHE_DIR=\/cache\/terraform\/plugin-cache/);
  assert.match(wrapper, /GRADLE_USER_HOME=\/cache\/gradle/);
  assert.match(wrapper, /PUB_CACHE=\/cache\/flutter\/pub-cache/);
  assert.match(wrapper, /npm_config_cache=\/cache\/npm/);
  assert.match(wrapper, /id -G/);
  assert.match(wrapper, /--group-add/);
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
  assert.match(hostedVerifier, /scripts\/ci\/retry-command/);
});

test('Terraform provider-cache lock is scoped to initialization', () => {
  const wrapper = fs.readFileSync(verifier, 'utf8');
  const hostedVerifier = fs.readFileSync(
    path.join(root, 'scripts', 'ci', 'verify-local'),
    'utf8',
  );

  assert.match(wrapper, /TF_DATA_DIR=\/tmp\/aet-terraform-data/);
  assert.match(wrapper, /TF_PLUGIN_CACHE_DIR=\/cache\/terraform\/plugin-cache/);
  assert.match(wrapper, /TF_PLUGIN_CACHE_LOCK_FILE=\/cache\/terraform\/plugin-cache\.lock/);
  assert.match(wrapper, /plugin-cache\.lock/);
  assert.doesNotMatch(wrapper, /flock/);
  assert.match(
    hostedVerifier,
    /flock "\$TF_PLUGIN_CACHE_LOCK_FILE" \\\n\s*\.\/scripts\/ci\/retry-command "Terraform provider initialization" terraform -chdir=terraform init/,
  );
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

  assert.match(runbook, /D1 (hosted baseline|comparison)/);
  assert.match(runbook, /post-merge release/);
  assert.match(runbook, /D3/);
  assert.match(runbook, /DynamoDB local/i);
  assert.match(runbook, /host-side preflight also requires `curl`/);
  assert.match(runbook, /Docker image and pinned toolchain sources/);
  assert.match(runbook, /Playwright\s+Chromium CDN mirror/);
  assert.match(runbook, /Maven Central, Terraform\s+Registry and releases/);
  assert.match(runbook, /only a host\s+reachability\s+check/);
  assert.match(runbook, /AWS credential/);
  assert.match(runbook, /AWS_EC2_METADATA_DISABLED=true/);
  assert.match(runbook, /AWS SDK\/CLI/);
  assert.match(runbook, /raw HTTP requests\s+to IMDS are not filtered/);
  assert.match(
    runbook,
    /not treat the container as an isolation boundary\s+for untrusted code/,
  );
  assert.match(runbook, /Git worktree/);
  assert.match(runbook, /detached Git worktree at/);
  assert.match(runbook, /invoking checkout itself is never mounted/);
  assert.match(runbook, /common directory/);
  assert.match(runbook, /non-zero/);
});

// Contract tests intentionally exercise the public script seams.
