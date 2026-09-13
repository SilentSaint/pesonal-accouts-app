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
  printf '%s\\n' "ap-south-1"
fi
if [[ "\${1:-}" == "print-env" ]]; then
  printf 'AWS_PROFILE=%s\\nAWS_CREDENTIAL_PROCESS=%s\\n' "\${AWS_PROFILE:-}" "\${AWS_CREDENTIAL_PROCESS:-}"
fi
if [[ "\${1:-}" == "login" ]]; then
  printf '%s\\n' "$*"
fi
`,
  );
  chmodSync(fakeAws, 0o700);
  return { directory, fakeAws };
}

test('setup configures a process profile backed by the login profile', () => {
  const { directory, fakeAws } = fakeAwsDirectory();
  const result = spawnSync('bash', [helper, 'setup'], {
    encoding: 'utf8',
    env: {
      ...process.env,
      AWS_CLI_COMMAND: fakeAws,
      AWS_LOGIN_PROFILE: 'default',
      AWS_PROCESS_PROFILE: 'agent-login',
    },
  });

  assert.equal(result.status, 0, result.stderr);
  const calls = readFileSync(path.join(directory, 'calls'), 'utf8');
  assert.match(calls, /configure get region --profile default/);
  assert.match(
    calls,
    /configure set credential_process \/tmp\/aws-dev-auth-test-[^ ]+\/aws configure export-credentials --profile default --format process --profile agent-login/,
  );
  assert.match(calls, /configure set region ap-south-1 --profile agent-login/);
});

test('sourced environment uses the refreshable profile and keeps login on default', () => {
  const { fakeAws } = fakeAwsDirectory();
  const result = spawnSync(
    'bash',
    [
      '-c',
      'source "$1"; printf "profile=%s\\nprocess=%s\\n" "$AWS_PROFILE" "$AWS_CREDENTIAL_PROCESS"; aws_dev_login --remote',
      'bash',
      helper,
    ],
    {
      encoding: 'utf8',
      env: {
        ...process.env,
        AWS_CLI_COMMAND: fakeAws,
        AWS_LOGIN_PROFILE: 'default',
        AWS_PROCESS_PROFILE: 'agent-login',
      },
    },
  );

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^profile=agent-login\n/);
  assert.match(
    result.stdout,
    /process=.*configure export-credentials --profile default --format process/,
  );
  assert.match(result.stdout, /login --profile default --remote/);
});

test('setup rejects using the same profile for login and process credentials', () => {
  const { fakeAws } = fakeAwsDirectory();
  const result = spawnSync('bash', [helper, 'setup'], {
    encoding: 'utf8',
    env: {
      ...process.env,
      AWS_CLI_COMMAND: fakeAws,
      AWS_LOGIN_PROFILE: 'default',
      AWS_PROCESS_PROFILE: 'default',
    },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /must be different/);
});
