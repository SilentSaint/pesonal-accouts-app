const assert = require('node:assert/strict');
const { chmodSync, mkdtempSync, readFileSync, writeFileSync } = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');

const repoRoot = path.resolve(__dirname, '..', '..');
const helper = path.join(repoRoot, 'scripts', 'aws-dev-auth.sh');

function fakeAwsDirectory() {
  const directory = mkdtempSync(path.join(os.tmpdir(), 'aws-dev-auth-test-'));
  const fakeAws = path.join(directory, 'aws');
  writeFileSync(
    fakeAws,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "${directory}/calls"
if [[ "\${1:-}" == "configure" && "\${2:-}" == "get" ]]; then
  printf '%s\\n' "ap-south-2"
fi
if [[ "\${1:-}" == "login" ]]; then
  if [[ "\${AWS_FAKE_LOGIN_FAILURE:-}" == "1" ]]; then
    exit 23
  fi
  printf '%s\\n' "$*"
fi
`,
  );
  chmodSync(fakeAws, 0o700);
  return { directory, fakeAws };
}

function authEnv(fakeAws, overrides = {}) {
  return {
    ...process.env,
    AWS_CLI_COMMAND: fakeAws,
    AWS_LOGIN_PROFILE: 'default',
    AWS_PROCESS_PROFILE: 'agent-login',
    ...overrides,
  };
}

test('setup configures agent-login from the default login profile', () => {
  const { directory, fakeAws } = fakeAwsDirectory();
  const result = spawnSync('bash', [helper, 'setup'], {
    encoding: 'utf8',
    env: authEnv(fakeAws),
  });

  assert.equal(result.status, 0, result.stderr);
  const calls = readFileSync(path.join(directory, 'calls'), 'utf8');
  assert.match(calls, /configure get region --profile default/);
  assert.match(
    calls,
    /configure set credential_process \/tmp\/aws-dev-auth-test-[^ ]+\/aws configure export-credentials --profile default --format process --region us-east-1 --profile agent-login/,
  );
  assert.match(calls, /configure set region ap-south-2 --profile agent-login/);
});

test('sourcing exports the process profile and preserves the login profile', () => {
  const { fakeAws } = fakeAwsDirectory();
  const result = spawnSync(
    'bash',
    [
      '-c',
      'source "$1"; printf "profile=%s\\nprocess=%s\\n" "$AWS_PROFILE" "$AWS_CREDENTIAL_PROCESS"; aws_dev_login --remote --region ap-south-2',
      'bash',
      helper,
    ],
    { encoding: 'utf8', env: authEnv(fakeAws) },
  );

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^profile=agent-login\n/);
  assert.match(result.stdout, /process=.*configure export-credentials --profile default --format process/);
  assert.match(result.stdout, /login --profile default --remote --region us-east-1/);
  assert.doesNotMatch(result.stdout, /login .*ap-south-2/);
});

test('sourcing does not enable errexit and failed login returns to the caller', () => {
  const { fakeAws } = fakeAwsDirectory();
  const result = spawnSync(
    'bash',
    [
      '-c',
      'set +e; source "$1"; case "$-" in *e*) exit 1;; esac; aws_dev_login --remote; status=$?; printf "shell-alive=%s\\n" "$status"',
      'bash',
      helper,
    ],
    { encoding: 'utf8', env: authEnv(fakeAws, { AWS_FAKE_LOGIN_FAILURE: '1' }) },
  );

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, 'shell-alive=23\n');
});

test('setup rejects using the same login and process profile', () => {
  const { fakeAws } = fakeAwsDirectory();
  const result = spawnSync('bash', [helper, 'setup'], {
    encoding: 'utf8',
    env: authEnv(fakeAws, { AWS_PROCESS_PROFILE: 'default' }),
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /must be different/);
});
