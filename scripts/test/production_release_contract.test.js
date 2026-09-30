const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
const deployScriptSource = path.join(root, 'scripts', 'deploy_and_build.sh');

function writeExecutable(file, contents) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, contents);
  fs.chmodSync(file, 0o755);
}

function createFixture() {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'aet-release-contract-'));
  const bin = path.join(fixture, 'bin');
  const log = path.join(fixture, 'events.log');
  const planJson = path.join(fixture, 'plan.json');

  fs.writeFileSync(log, '');
  fs.mkdirSync(path.join(fixture, 'scripts'), { recursive: true });
  fs.mkdirSync(path.join(fixture, 'terraform'), { recursive: true });
  fs.mkdirSync(path.join(fixture, 'frontend'), { recursive: true });
  fs.copyFileSync(deployScriptSource, path.join(fixture, 'scripts', 'deploy_and_build.sh'));
  fs.chmodSync(path.join(fixture, 'scripts', 'deploy_and_build.sh'), 0o755);

  writeExecutable(
    path.join(fixture, 'backend', 'lambda', 'build.sh'),
    '#!/usr/bin/env bash\nprintf "lambda-build\\n" >> "$AET_TEST_LOG"\n',
  );
  writeExecutable(
    path.join(fixture, 'backend', 'gradlew'),
    '#!/usr/bin/env bash\nprintf "gradle %s\\n" "$*" >> "$AET_TEST_LOG"\n',
  );

  writeExecutable(
    path.join(bin, 'git'),
    `#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\\n' "$*" >> "$AET_TEST_LOG"
case "$*" in
  *"branch --show-current") printf 'main\\n' ;;
  *"rev-parse HEAD") printf 'release-sha\\n' ;;
  *"status --porcelain") ;;
esac
`,
  );

  writeExecutable(
    path.join(bin, 'terraform'),
    `#!/usr/bin/env bash
set -euo pipefail
printf 'terraform %s\\n' "$*" >> "$AET_TEST_LOG"
case "\${2:-}" in
  init)
    ;;
  plan)
    for argument in "$@"; do
      if [[ "$argument" == -out=* ]]; then
        touch "\${argument#-out=}"
      fi
    done
    ;;
  show)
    cat "$AET_TEST_PLAN_JSON"
    ;;
  apply)
    ;;
  output)
    output_name="\${4:?missing Terraform output name}"
    case "\${AET_TEST_OUTPUT_DRIFT:-0}:$output_name" in
      1:api_gateway_url) printf 'https://drift.example\\n' ;;
      *:api_gateway_url) printf 'https://api.example\\n' ;;
      *:websocket_sync_url) printf 'wss://websocket.example\\n' ;;
      *:s3_web_bucket_name) printf 'web-bucket\\n' ;;
      *:cloudfront_distribution_id) printf 'distribution\\n' ;;
      *:cloudfront_web_url) printf 'https://web.example\\n' ;;
      *) printf 'unknown-output\\n' ;;
    esac
    ;;
esac
`,
  );

  writeExecutable(
    path.join(bin, 'flutter'),
    `#!/usr/bin/env bash
set -euo pipefail
printf 'flutter %s\\n' "$*" >> "$AET_TEST_LOG"
if [[ "\${1:-}" == build && "\${2:-}" == web ]]; then
  if [[ "\${AET_TEST_FAIL_WEB:-0}" == 1 ]]; then
    exit 37
  fi
  mkdir -p build/web
  printf 'web\\n' > build/web/index.html
elif [[ "\${1:-}" == build && "\${2:-}" == apk ]]; then
  mkdir -p build/app/outputs/flutter-apk
  printf 'apk\\n' > build/app/outputs/flutter-apk/app-debug.apk
fi
`,
  );

  writeExecutable(
    path.join(bin, 'aws'),
    `#!/usr/bin/env bash
set -euo pipefail
printf 'aws %s\\n' "$*" >> "$AET_TEST_LOG"
if [[ "\${1:-}" == sts ]]; then
  printf '123\\n'
elif [[ "\${1:-}" == cloudfront && "\${2:-}" == create-invalidation ]]; then
  printf 'invalidation-123\\n'
fi
`,
  );

  writeExecutable(
    path.join(bin, 'curl'),
    `#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\\n' "$*" >> "$AET_TEST_LOG"
if [[ "$*" == *deployment-version.json* ]]; then
  printf '{"commit":"release-sha"}\\n'
else
  printf '{"status":"ok"}\\n'
fi
`,
  );

  fs.writeFileSync(
    planJson,
    JSON.stringify({
      planned_values: {
        outputs: {
          api_gateway_url: { value: 'https://api.example' },
          websocket_sync_url: { value: 'wss://websocket.example' },
          s3_web_bucket_name: { value: 'web-bucket' },
          cloudfront_distribution_id: { value: 'distribution' },
          cloudfront_web_url: { value: 'https://web.example' },
        },
      },
    }),
  );

  return { fixture, bin, log, planJson };
}

function runDeployment(fixture, overrides = {}) {
  const environment = {
    ...process.env,
    PATH: `${fixture.bin}:${process.env.PATH}`,
    AET_GUARDED_RELEASE: 'YES',
    AET_TEST_LOG: fixture.log,
    AET_TEST_PLAN_JSON: fixture.planJson,
    AWS_REGION: 'ap-south-2',
    AWS_ACCOUNT_ID: '123',
    ...overrides,
  };

  return spawnSync(path.join(fixture.fixture, 'scripts', 'deploy_and_build.sh'), [], {
    cwd: fixture.fixture,
    env: environment,
    encoding: 'utf8',
  });
}

function removeFixture(fixture) {
  fs.rmSync(fixture.fixture, { recursive: true, force: true });
}

test('a failed web build cannot reach Terraform apply', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, { AET_TEST_FAIL_WEB: '1' });
    const events = fs.readFileSync(fixture.log, 'utf8');

    assert.notEqual(result.status, 0, result.stdout);
    assert.match(events, /terraform .* plan/);
    assert.match(events, /flutter build web/);
    assert.doesNotMatch(events, /terraform .* apply/);
  } finally {
    removeFixture(fixture);
  }
});

test('applies the saved Terraform plan only after every release artifact builds', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture);
    const events = fs.readFileSync(fixture.log, 'utf8');
    const plan = events.indexOf('terraform -chdir=');
    const web = events.indexOf('flutter build web', plan + 1);
    const apk = events.indexOf('flutter build apk', web + 1);
    const apply = events.indexOf('terraform -chdir=', apk + 1);
    const publish = events.indexOf('aws s3 sync', apply + 1);
    const verify = events.indexOf('curl', publish + 1);

    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.ok(plan >= 0, 'Terraform planning should run');
    assert.ok(web > plan, 'web build must follow planning');
    assert.ok(apk > web, 'APK build must follow web build');
    assert.ok(apply > apk, 'Terraform apply must follow all artifact builds');
    assert.ok(publish > apply, 'publication must follow Terraform apply');
    assert.ok(verify > publish, 'live verification must follow publication');
    assert.match(events, /terraform .* apply .*automatic-expense-tracker-release-plan/);
  } finally {
    removeFixture(fixture);
  }
});

test('Terraform output drift stops publication after the saved plan is applied', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, { AET_TEST_OUTPUT_DRIFT: '1' });
    const events = fs.readFileSync(fixture.log, 'utf8');

    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, /Terraform output api_gateway_url changed/);
    assert.match(events, /terraform .* apply/);
    assert.doesNotMatch(events, /aws s3 sync/);
  } finally {
    removeFixture(fixture);
  }
});
