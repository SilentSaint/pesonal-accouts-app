const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const sourceRoot = path.resolve(__dirname, '../..');

function createFixture(t) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'expense-release-test-'));
  const root = path.join(temporary, 'checkout');
  const bin = path.join(temporary, 'bin');
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'frontend'), { recursive: true });
  fs.mkdirSync(bin);
  return {
    root,
    temporary,
    bin,
    copy(relativePath) {
      const destination = path.join(root, relativePath);
      fs.mkdirSync(path.dirname(destination), { recursive: true });
      fs.cpSync(path.join(sourceRoot, relativePath), destination, { recursive: true });
    },
    tool(name, script) {
      fs.writeFileSync(path.join(bin, name), `#!/usr/bin/env bash\nset -euo pipefail\n${script}\n`, { mode: 0o755 });
    },
    run(relativePath, environment = {}) {
      return spawnSync(path.join(root, relativePath), {
        cwd: root,
        encoding: 'utf8',
        timeout: 20_000,
        env: { ...process.env, ...environment, PATH: `${bin}:${process.env.PATH}` },
      });
    },
  };
}

function createReleaseFixture(t) {
  const fixture = createFixture(t);
  for (const relativePath of [
    'scripts', '.gitignore', 'backend/gradlew', 'backend/gradle',
    'backend/lambda', 'frontend/e2e_playwright_test.js',
  ]) fixture.copy(relativePath);
  fs.mkdirSync(path.join(fixture.root, 'terraform'));
  fixture.tool('chromium', 'exit 0');
  fixture.tool('java', `
if [[ "\${FAIL_RELEASE_STEP:-}" == "java test" && "$*" == *" test"* ]] ||
   [[ "\${FAIL_RELEASE_STEP:-}" == "java lambdaZip" && "$*" == *lambdaZip* ]]; then
  echo "deliberate Java readiness failure" >&2; exit 37
fi
if [[ "$*" != *lambdaZip* ]]; then exit 0; fi
mkdir -p "$TEST_RELEASE_ROOT/backend/build/lambda"
python3 - "$TEST_RELEASE_ROOT/backend/build/lambda/transaction-command-lambda.zip" <<'PY'
import sys, zipfile, uuid
with zipfile.ZipFile(sys.argv[1], 'w') as archive:
    archive.writestr('lib/application.jar', 'compiled test application ' + str(uuid.uuid4()))
PY`);
  fixture.tool('terraform', `
if [[ "\${FAIL_RELEASE_STEP:-}" == "terraform $1" ]]; then
  echo "deliberate Terraform $1 failure" >&2
  exit 37
fi
case "$1" in
  init|fmt|validate) ;;
  plan)
    for arg in "$@"; do
      if [[ "$arg" == -out=* ]]; then plan="\${arg#-out=}"; fi
    done
    test -n "\${plan:-}" || { echo "A saved plan is required" >&2; exit 98; }
    "${process.execPath}" - "$plan" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const outputs = {
  api_gateway_url: { value: 'https://api.example.invalid' },
  websocket_sync_url: { value: 'wss://socket.example.invalid' },
  s3_web_bucket_name: { value: 'release-test-web' },
  cloudfront_distribution_id: { value: 'DISTRIBUTION1' },
  cloudfront_web_url: { value: 'https://web.example.invalid' },
};
const resources = [
  ['api_handler', 'node', '../backend/lambda/lambda.zip'],
  ['command_handler', 'java', '../backend/build/lambda/transaction-command-lambda.zip'],
].map(([name, runtime, filename]) => ({
  address: 'aws_lambda_function.' + name, mode: 'managed', type: 'aws_lambda_function',
  values: {
    function_name: 'release-test-' + runtime,
    filename,
    source_code_hash: createHash('sha256').update(fs.readFileSync(
      path.resolve(process.env.TEST_RELEASE_ROOT, 'terraform', filename),
    )).digest('base64'),
  },
}));
const changes = [{
  address: 'aws_lambda_function.api_handler', type: 'aws_lambda_function',
  change: { actions: ['update'], before: { source_code_hash: 'old' }, after: { source_code_hash: 'new' } },
}];
const scenario = process.env.TEST_PLAN_SCENARIO;
if (scenario === 'changed endpoint') outputs.api_gateway_url.value = 'https://different.example.invalid';
if (scenario === 'unknown endpoint') delete outputs.websocket_sync_url.value;
if (scenario === 'missing target') delete outputs.s3_web_bucket_name;
if (scenario === 'wrong Lambda hash') resources[0].values.source_code_hash = 'old-deployed-code';
if (scenario === 'unknown Lambda archive') delete resources[0].values.filename;
if (scenario === 'destroy') changes[0].change.actions = ['delete'];
if (scenario === 'replace') changes[0].change.actions = ['delete', 'create'];
if (scenario === 'new alarm') changes.push({
  address: 'aws_cloudwatch_metric_alarm.new_alarm', type: 'aws_cloudwatch_metric_alarm',
  change: { actions: ['create'], after: { alarm_name: 'not approved' } },
});
fs.writeFileSync(process.argv[2], JSON.stringify({
  format_version: '1.2', errored: false,
  variables: {
    aws_region: { value: scenario === 'wrong region' ? 'us-east-1' : 'ap-south-2' },
    environment: { value: scenario === 'renamed stack' ? 'prod' : 'dev' },
  },
  planned_values: { outputs, root_module: { resources } },
  resource_changes: changes,
}));
JS
    touch "$TEST_RELEASE_PLANNED"
    ;;
  show)
    if [[ "\${TEST_PLAN_SCENARIO:-}" == "malformed private JSON" ]]; then
      printf 'private-plan-value: invalid JSON'
    else
      cat "\${*: -1}"
    fi
    if [[ -n "\${TEST_MUTATE_ARTIFACT:-}" ]]; then
      directory="$(dirname "\${*: -1}")"
      case "$TEST_MUTATE_ARTIFACT" in
        source) echo "// concurrent source edit" >> "$TEST_RELEASE_ROOT/backend/lambda/index.js" ;;
        plan) echo "corrupt plan" >> "\${*: -1}" ;;
        lambda) echo "corrupt archive" >> "$TEST_RELEASE_ROOT/backend/lambda/lambda.zip" ;;
        java) echo "corrupt archive" >> "$directory/java.zip" ;;
        web) echo "unchecked web" >> "$directory/web/index.html" ;;
        lease) printf '{"owner":{"S":"replacement-owner"}}' > "$TEST_RELEASE_LEASE" ;;
        evidence) echo "changed source evidence" >> "$directory/source.tar" ;;
      esac
    fi ;;
  apply)
    test -f "\${*: -1}" || { echo "Only a saved plan can be applied" >&2; exit 98; }
    mkdir -p "$TEST_RELEASE_DEPLOYED"
    cp "$TEST_RELEASE_ROOT/backend/lambda/lambda.zip" "$TEST_RELEASE_DEPLOYED/node.zip"
    cp "$TEST_RELEASE_ROOT/backend/build/lambda/transaction-command-lambda.zip" "$TEST_RELEASE_DEPLOYED/java.zip"
    if [[ "\${TEST_MUTATE_AFTER_APPLY:-}" == "1" ]]; then
      echo "changed after apply" >> "$(dirname "\${*: -1}")/web/index.html"
    fi
    echo "infrastructure applied" > "$TEST_RELEASE_INFRA" ;;
  output)
    if [[ "\${TEST_EMPTY_OUTPUT:-}" == "\${*: -1}" ]]; then exit 0; fi
    case "\${*: -1}" in
      api_gateway_url) echo "https://api.example.invalid" ;;
      websocket_sync_url) echo "wss://socket.example.invalid" ;;
      s3_web_bucket_name) echo "release-test-web" ;;
      cloudfront_distribution_id) echo "DISTRIBUTION1" ;;
      cloudfront_web_url) echo "https://web.example.invalid" ;;
      *) echo "Unsupported Terraform fixture output" >&2; exit 98 ;;
    esac ;;
  *) echo "Unsupported Terraform fixture command" >&2; exit 98 ;;
esac`);
  fixture.tool('flutter', `
if [[ -n "\${FAIL_RELEASE_STEP:-}" && "flutter $*" == "\${FAIL_RELEASE_STEP}"* ]]; then
  echo "deliberate $FAIL_RELEASE_STEP failure" >&2
  exit 37
fi
case "$1" in
  pub|analyze|test) ;;
  build)
    if [[ "$2" == "web" ]]; then
      output="$TEST_RELEASE_ROOT/frontend/build/web"
      content="candidate web bundle"
      if [[ "$*" == *"--dart-define=API_BASE_URL="* ]]; then
        content="configured release bundle"
      fi
      shift 2
      while [[ "$#" -gt 0 ]]; do
        case "$1" in
          --output) output="$2"; shift 2 ;;
          --output=*) output="\${1#--output=}"; shift ;;
          *) shift ;;
        esac
      done
      mkdir -p "$output"
      echo "$content" > "$output/index.html"
      if [[ -n "\${TEST_MARKER_TARGET:-}" ]]; then
        ln -s "$TEST_MARKER_TARGET" "$output/deployment-version.json"
      fi
      if [[ "$content" == "configured release bundle" && -n "\${TEST_MUTATE_SOURCE:-}" ]]; then
        echo "// source changed during preparation" >> "$TEST_RELEASE_ROOT/backend/lambda/index.js"
        if [[ "$TEST_MUTATE_SOURCE" == "committed" ]]; then
          git -C "$TEST_RELEASE_ROOT" -c user.name=Fixture -c user.email=fixture@example.invalid \
            -c commit.gpgsign=false commit --quiet -am "Concurrent source change"
        fi
      fi
    elif [[ "$2" == "apk" ]]; then
      mkdir -p "$TEST_RELEASE_ROOT/frontend/build/app/outputs/flutter-apk"
      echo "candidate apk" > "$TEST_RELEASE_ROOT/frontend/build/app/outputs/flutter-apk/app-debug.apk"
      if [[ "\${TEST_MUTATE_CHECKED:-}" == "lambda" ]]; then
        echo "unchecked lambda" >> "$TEST_RELEASE_ROOT/backend/lambda/lambda.zip"
      elif [[ "\${TEST_MUTATE_CHECKED:-}" == "web" ]]; then
        echo "unchecked web" >> "$TEST_RELEASE_ROOT/frontend/build/web/index.html"
      fi
    else exit 98; fi ;;
  *) exit 98 ;;
esac`);
  fixture.tool('aws', `
if [[ "\${FAIL_RELEASE_STEP:-}" == "aws $1 $2" ]]; then
  echo "deliberate AWS $1 $2 failure" >&2
  exit 37
fi
case "$1 $2" in
  "lambda get-function-configuration")
    "${process.execPath}" - "$@" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const args = process.argv.slice(2);
const name = args[args.indexOf('--function-name') + 1];
const archive = name === 'release-test-node' ? 'node.zip' : 'java.zip';
console.log(JSON.stringify({
  CodeSha256: process.env.TEST_LIVE_LAMBDA === 'old code' ? 'old-code' :
    createHash('sha256').update(fs.readFileSync(path.join(process.env.TEST_RELEASE_DEPLOYED, archive))).digest('base64'),
  State: process.env.TEST_LIVE_LAMBDA === 'inactive' ? 'Pending' : 'Active',
  LastUpdateStatus: 'Successful',
}));
if (process.env.TEST_MUTATE_DURING_LIVE_CHECK === '1') {
  const releases = path.join(process.env.TEST_RELEASE_ROOT, 'dev_builds/releases');
  const directory = path.join(releases, fs.readdirSync(releases)[0]);
  fs.appendFileSync(path.join(directory, 'web/index.html'), 'unchecked later bytes');
}
JS
    ;;
  "dynamodb put-item"|"dynamodb get-item"|"dynamodb delete-item")
    "${process.execPath}" - "$@" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const args = process.argv.slice(2);
const option = (name) => args[args.indexOf(name) + 1];
assert.equal(option('--table-name'), 'ExpenseTrackerData');
const file = process.env.TEST_RELEASE_LEASE;
if (args[1] === 'put-item') {
  const item = JSON.parse(option('--item'));
  assert.deepEqual(item.PK, { S: 'RELEASE#production' });
  assert.deepEqual(item.SK, { S: 'LEASE' });
  assert.equal(option('--condition-expression'), 'attribute_not_exists(PK)');
  assert.equal(item.ttl, undefined, 'A live release lock must not silently expire');
  try { fs.writeFileSync(file, JSON.stringify(item), { flag: 'wx' }); }
  catch (error) { if (error.code !== 'EEXIST') throw error; console.error('ConditionalCheckFailedException: release held'); process.exit(37); }
} else if (args[1] === 'get-item') {
  assert.ok(args.includes('--consistent-read'));
  console.log(fs.existsSync(file) ? JSON.stringify({ Item: JSON.parse(fs.readFileSync(file)) }) : '{}');
} else {
  assert.equal(option('--condition-expression'), '#owner = :owner');
  assert.deepEqual(JSON.parse(option('--expression-attribute-names')), { '#owner': 'owner' });
  const owner = JSON.parse(option('--expression-attribute-values'))[':owner'];
  if (!fs.existsSync(file) || JSON.parse(fs.readFileSync(file)).owner.S !== owner.S) {
    console.error('ConditionalCheckFailedException: release owner changed'); process.exit(37);
  }
  fs.unlinkSync(file);
}
JS
    ;;
  "sts get-caller-identity")
    arn="\${TEST_AWS_ARN:-arn:aws:sts::111111111111:assumed-role/release/session}"
    if [[ -f "$TEST_RELEASE_PLANNED" && "\${TEST_CHANGED_IDENTITY:-}" == "1" ]]; then
      arn="arn:aws:sts::111111111111:assumed-role/other/session"
    fi
    if [[ "$*" == *"--query Account"* ]]; then echo "\${TEST_AWS_ACCOUNT:-111111111111}"
    elif [[ "$*" == *"--query Arn"* ]]; then echo "$arn"
    else printf '{"Account":"%s","Arn":"arn:aws:sts::%s:assumed-role/release/session"}\\n' "\${TEST_AWS_ACCOUNT:-111111111111}" "\${TEST_AWS_ACCOUNT:-111111111111}"; fi ;;
  "s3 cp"|"s3 sync")
    mkdir -p "$TEST_RELEASE_CLOUD"
    cp -R "$3/." "$TEST_RELEASE_CLOUD/" ;;
  "cloudfront create-invalidation") echo "INVALIDATION1" ;;
  "cloudfront wait")
    if [[ "\${TEST_REPLACE_LEASE_AT_END:-}" == "1" ]]; then
      printf '{"owner":{"S":"replacement-owner"}}' > "$TEST_RELEASE_LEASE"
    fi ;;
  *) echo "Unsupported AWS fixture command" >&2; exit 98 ;;
esac`);
  fixture.tool('node', `
if [[ "\${1:-}" == "--test" ]]; then
  if [[ "\${TEST_FAIL_RELEASE_CONTRACT:-}" == "1" && "$*" == *"/scripts/test/"* ]]; then
    echo "deliberate public release contract failure" >&2; exit 37
  fi
  if [[ "\${FAIL_RELEASE_STEP:-}" == "node --test" ]]; then
    echo "deliberate Node test failure" >&2
    exit 37
  fi
  if [[ "$*" == *"/backend/lambda/test/"* ]]; then
    cp "$TEST_RELEASE_ROOT/backend/build/lambda/transaction-command-lambda.zip" "$TEST_RELEASE_CHECKED_JAVA"
  fi
  exit 0
fi
if [[ "\${1:-}" == "-e" && "\${2:-}" == 'require.resolve("playwright")' ]]; then
  if [[ "\${TEST_PLAYWRIGHT_MISSING:-}" == "1" && ! -f "$TEST_RELEASE_NPM" ]]; then exit 1; fi
  exit 0
fi
if [[ "\${1:-}" == *"/e2e_playwright_test.js" || "\${1:-}" == "e2e_playwright_test.js" ]]; then
  test -f "$TEST_RELEASE_ROOT/frontend/build/web/index.html" || {
    echo "Browser readiness has no candidate web bundle" >&2
    exit 37
  }
  if [[ "\${TEST_BROWSER_FAIL_CONFIGURED:-}" == "1" ]] &&
    grep -q 'configured release bundle' "$TEST_RELEASE_ROOT/frontend/build/web/index.html"; then
    echo "Configured release bundle failed browser readiness" >&2
    exit 37
  fi
  exit 0
fi
exec "${process.execPath}" "$@"`);
  fixture.tool('npm', `
test "$*" = "install --no-save --no-package-lock playwright@1.47.2" || exit 98
echo "installed pinned browser client" > "$TEST_RELEASE_NPM"`);
  fixture.tool('curl', `
if [[ "\${FAIL_RELEASE_STEP:-}" == "curl health" && "$*" == *"/api/health"* ]]; then
  echo "deliberate API health failure" >&2; exit 37
fi
if [[ "$*" == *"deployment-version.json"* ]]; then
  if [[ -n "\${TEST_LIVE_COMMIT:-}" ]]; then
    printf '{"commit":"%s"}\\n' "$TEST_LIVE_COMMIT"
  else
    cat "$TEST_RELEASE_CLOUD/deployment-version.json"
  fi
elif [[ "$*" == *"/api/health"* ]]; then
  echo '{"status":"ok"}'
else
  echo "Unsupported HTTP fixture request" >&2
  exit 98
fi`);
  const git = (...args) => execFileSync('git', [
    '-c', 'user.name=Release fixture',
    '-c', 'user.email=release@example.invalid',
    '-c', 'commit.gpgsign=false',
    ...args,
  ], { cwd: fixture.root, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  git('init', '--quiet', '--initial-branch=main');
  git('add', '.');
  git('commit', '--quiet', '-m', 'Release fixture');
  const origin = path.join(fixture.temporary, 'origin.git');
  git('clone', '--quiet', '--bare', fixture.root, origin);
  git('remote', 'add', 'origin', origin);
  git('fetch', '--quiet', 'origin', 'main');
  const environment = {
    PRODUCTION_DEPLOY_APPROVED: 'YES',
    AWS_ACCOUNT_ID: '111111111111',
    AWS_REGION: 'ap-south-2',
    AWS_DEPLOY_ROLE_ARN: 'arn:aws:iam::111111111111:role/release',
    JAVA_HOME: fixture.temporary,
    TEST_RELEASE_ROOT: fixture.root,
    TEST_RELEASE_CLOUD: path.join(fixture.temporary, 'published'),
    TEST_RELEASE_INFRA: path.join(fixture.temporary, 'infrastructure'),
    TEST_RELEASE_CHECKED_JAVA: path.join(fixture.temporary, 'checked-java.zip'),
    TEST_RELEASE_PLANNED: path.join(fixture.temporary, 'planned'),
    TEST_RELEASE_LEASE: path.join(fixture.temporary, 'lease.json'),
    TEST_RELEASE_DEPLOYED: path.join(fixture.temporary, 'deployed'),
    AWS_DEFAULT_REGION: 'ap-south-2',
    TEST_RELEASE_NPM: path.join(fixture.temporary, 'npm-installed'),
    E2E_BROWSER_EXECUTABLE: path.join(fixture.bin, 'chromium'),
    GITHUB_ACTIONS: '',
  };
  return { ...fixture, git, environment };
}

test('local analysis accepts informational diagnostics under the same policy as CI', (t) => {
  const fixture = createFixture(t);
  fixture.copy('scripts/ci/static-analysis');
  fixture.tool('flutter', `
if [[ "$1" == "analyze" ]]; then
  echo "44 informational diagnostics"
  [[ " $* " == *" --no-fatal-infos "* ]] || exit 1
fi`);

  const result = fixture.run('scripts/ci/static-analysis');

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /44 informational diagnostics/);
});

test('local analysis still rejects analyzer warnings', (t) => {
  const fixture = createFixture(t);
  fixture.copy('scripts/ci/static-analysis');
  fixture.tool('flutter', `
if [[ "$1" == "analyze" ]]; then
  echo "analyzer warning" >&2
  [[ " $* " == *" --no-fatal-warnings "* ]] || exit 1
fi`);

  const result = fixture.run('scripts/ci/static-analysis');

  assert.equal(result.status, 1);
  assert.match(result.stderr, /analyzer warning/);
});

test('the documented manual entrypoint executes and rejects missing owner approval', (t) => {
  const fixture = createFixture(t);
  fixture.copy('scripts');

  const result = fixture.run('scripts/manual_production_deploy.sh', {
    PRODUCTION_DEPLOY_APPROVED: '',
  });

  assert.equal(result.error, undefined);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Refusing production deployment.*explicit owner approval/);
});

test('a failed Terraform apply cannot publish a frontend or report a successful release', (t) => {
  const fixture = createReleaseFixture(t);

  const result = fixture.run('scripts/deploy_and_build.sh', {
    ...fixture.environment,
    FAIL_RELEASE_STEP: 'terraform apply',
  });

  assert.equal(result.error, undefined);
  assert.notEqual(result.status, 0, result.stdout);
  assert.match(result.stderr, /Terraform apply failed/);
  const releases = path.join(fixture.root, 'dev_builds/releases');
  const directory = path.join(releases, fs.readdirSync(releases)[0]);
  assert.match(fs.readFileSync(path.join(directory, 'terraform-apply.log'), 'utf8'), /deliberate Terraform apply failure/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
  assert.doesNotMatch(result.stdout, /Completed Successfully/);
});

test('calling the delegated deployment entrypoint cannot bypass owner approval', (t) => {
  const fixture = createReleaseFixture(t);

  const result = fixture.run('scripts/deploy_and_build.sh', {
    ...fixture.environment,
    PRODUCTION_DEPLOY_APPROVED: '',
  });

  assert.equal(result.status, 1, result.stdout || result.stderr);
  assert.match(result.stderr, /Refusing production deployment.*explicit owner approval/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
});

for (const [name, prepare, message] of [
  ['a non-main branch', (fixture) => fixture.git('checkout', '--quiet', '-b', 'feature'), /must be on main/],
  ['a detached checkout', (fixture) => fixture.git('checkout', '--quiet', '--detach'), /must be on main/],
  ['uncommitted files', (fixture) => fs.writeFileSync(path.join(fixture.root, 'uncommitted.txt'), 'not reviewed'), /working tree must be clean/],
  ['main behind the remote', (fixture) => {
    const revision = fixture.git('commit-tree', 'HEAD^{tree}', '-p', 'HEAD', '-m', 'New remote revision').trim();
    fixture.git('push', '--quiet', 'origin', `${revision}:refs/heads/main`);
  }, /exactly match origin\/main/],
]) {
  test(`the manual hatch refuses ${name} before changing infrastructure`, (t) => {
    const fixture = createReleaseFixture(t);
    prepare(fixture);

    const result = fixture.run('scripts/manual_production_deploy.sh', fixture.environment);

    assert.equal(result.status, 1, result.stdout || result.stderr);
    assert.match(result.stderr, message);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
  });
}

test('valid credentials for another AWS account cannot change infrastructure', (t) => {
  const fixture = createReleaseFixture(t);

  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment,
    TEST_AWS_ACCOUNT: '222222222222',
  });

  assert.equal(result.status, 1, result.stdout || result.stderr);
  assert.match(result.stderr, /AWS account/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
});

test('a failed web build leaves infrastructure and the published application unchanged', (t) => {
  const fixture = createReleaseFixture(t);

  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment,
    FAIL_RELEASE_STEP: 'flutter build web',
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /deliberate flutter build web failure/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
});

test('a successful release publishes its exact source and Lambda artifact identities', (t) => {
  const fixture = createReleaseFixture(t);

  const result = fixture.run('scripts/manual_production_deploy.sh', fixture.environment);

  assert.equal(result.status, 0, result.stdout || result.stderr);
  const markerPath = path.join(fixture.environment.TEST_RELEASE_CLOUD, 'deployment-version.json');
  assert.equal(fs.existsSync(markerPath), true, 'A release must publish a version marker');
  const marker = JSON.parse(fs.readFileSync(markerPath, 'utf8'));
  const hash = (relativePath) => createHash('sha256')
    .update(fs.readFileSync(path.join(fixture.root, relativePath))).digest('hex');
  assert.equal(marker.commit, fixture.git('rev-parse', 'HEAD').trim());
  assert.equal(marker.nodeSha256, hash('backend/lambda/lambda.zip'));
  assert.equal(marker.javaSha256, hash('backend/build/lambda/transaction-command-lambda.zip'));
  assert.equal(marker.javaSha256, createHash('sha256')
    .update(fs.readFileSync(fixture.environment.TEST_RELEASE_CHECKED_JAVA)).digest('hex'),
  'The archive that passed readiness must not be replaced by a later rebuild');
  assert.match(marker.webSha256, /^[a-f0-9]{64}$/);
  const archived = path.join(fixture.root, 'dev_builds', 'releases', marker.releaseId);
  assert.equal(fs.existsSync(path.join(archived, 'node.zip')), true);
  assert.equal(fs.existsSync(path.join(archived, 'java.zip')), true);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(archived, 'manifest.json'), 'utf8')), marker);
  assert.equal(JSON.parse(fs.readFileSync(path.join(archived, 'status.json'))).status, 'verified');
  const provenance = JSON.parse(fs.readFileSync(path.join(archived, 'provenance.json')));
  assert.equal(provenance.commit, marker.commit);
  assert.equal(provenance.region, 'ap-south-2');
  assert.equal(provenance.environment, 'dev');
  assert.equal(provenance.apiBaseUrl, 'https://api.example.invalid/api');
  assert.equal(provenance.websocketUrl, 'wss://socket.example.invalid');
  assert.equal(fs.existsSync(path.join(archived, 'source.tar')), true);
  assert.equal(fs.existsSync(path.join(fixture.environment.TEST_RELEASE_CLOUD, 'terraform.plan')), false);
  assert.equal(fs.existsSync(path.join(fixture.environment.TEST_RELEASE_CLOUD, 'provenance.json')), false);
});

test('a stale live version prevents a successful release result even after upload', (t) => {
  const fixture = createReleaseFixture(t);

  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment,
    TEST_LIVE_COMMIT: '0'.repeat(40),
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /release marker.*does not match/);
  assert.doesNotMatch(result.stdout, /Completed Successfully/);
});

for (const output of [
  'api_gateway_url', 'websocket_sync_url', 's3_web_bucket_name',
  'cloudfront_distribution_id', 'cloudfront_web_url',
]) {
  test(`missing deployment output ${output} cannot change production`, (t) => {
    const fixture = createReleaseFixture(t);

    const result = fixture.run('scripts/manual_production_deploy.sh', {
      ...fixture.environment,
      TEST_EMPTY_OUTPUT: output,
    });

    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, new RegExp(output));
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
  });
}

test('failed Lambda and archive tests block deployment before infrastructure changes', (t) => {
  const fixture = createReleaseFixture(t);

  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment,
    FAIL_RELEASE_STEP: 'node --test',
  });

  assert.notEqual(result.status, 0, result.stdout);
  assert.match(result.stderr, /deliberate Node test failure/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
});

test('the gated CI main revision uses the same release path from its detached checkout', (t) => {
  const fixture = createReleaseFixture(t);
  const revision = fixture.git('rev-parse', 'HEAD').trim();
  fixture.git('checkout', '--quiet', '--detach');

  const result = fixture.run('scripts/deploy_and_build.sh', {
    ...fixture.environment,
    GITHUB_ACTIONS: 'true',
    GITHUB_REF: 'refs/heads/main',
    GITHUB_SHA: revision,
  });

  assert.equal(result.status, 0, result.stdout || result.stderr);
  const marker = JSON.parse(fs.readFileSync(path.join(
    fixture.environment.TEST_RELEASE_CLOUD, 'deployment-version.json',
  ), 'utf8'));
  assert.equal(marker.commit, revision);
});

for (const [name, environment] of [
  ['a different ref', { GITHUB_REF: 'refs/heads/feature' }],
  ['a different revision', { GITHUB_SHA: '0'.repeat(40) }],
]) {
  test(`CI cannot deploy ${name} by claiming to be the main job`, (t) => {
    const fixture = createReleaseFixture(t);

    const result = fixture.run('scripts/deploy_and_build.sh', {
      ...fixture.environment,
      GITHUB_ACTIONS: 'true',
      GITHUB_REF: 'refs/heads/main',
      GITHUB_SHA: fixture.git('rev-parse', 'HEAD').trim(),
      ...environment,
    });

    assert.equal(result.status, 1);
    assert.match(result.stderr, /CI must use its gated main revision/);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
  });
}

test('installed browser dependencies do not become unreviewed source files', (t) => {
  const fixture = createReleaseFixture(t);
  const dependency = path.join(fixture.root, 'frontend/node_modules/playwright/index.js');
  fs.mkdirSync(path.dirname(dependency), { recursive: true });
  fs.writeFileSync(dependency, 'installed browser client');

  const result = fixture.run('scripts/manual_production_deploy.sh', fixture.environment);

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.existsSync(path.join(fixture.environment.TEST_RELEASE_CLOUD, 'deployment-version.json')), true);
});

test('the endpoint-configured release bundle must pass its own browser gate', (t) => {
  const fixture = createReleaseFixture(t);

  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment,
    TEST_BROWSER_FAIL_CONFIGURED: '1',
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Configured release bundle failed browser readiness/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
});

for (const change of ['uncommitted', 'committed']) {
  test(`a ${change} source change during preparation cannot be deployed`, (t) => {
    const fixture = createReleaseFixture(t);

    const result = fixture.run('scripts/manual_production_deploy.sh', {
      ...fixture.environment,
      TEST_MUTATE_SOURCE: change,
    });

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /candidate source changed/);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
  });
}

test('a source inspection failure cannot be interpreted as a clean checkout', (t) => {
  const fixture = createReleaseFixture(t);
  const gitExecutable = execFileSync('sh', ['-c', 'command -v git'], { encoding: 'utf8' }).trim();
  fixture.tool('git', `
if [[ "$1" == "status" ]]; then
  echo "cannot inspect working tree" >&2
  exit 128
fi
exec ${JSON.stringify(gitExecutable)} "$@"`);

  const result = fixture.run('scripts/manual_production_deploy.sh', fixture.environment);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /cannot inspect working tree/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
});

test('a failed saved-plan preparation cannot mutate production', (t) => {
  const fixture = createReleaseFixture(t);
  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment,
    FAIL_RELEASE_STEP: 'terraform plan',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Terraform plan failed/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
});

for (const scenario of [
  'changed endpoint', 'unknown endpoint', 'missing target', 'destroy', 'replace', 'new alarm',
  'wrong region', 'renamed stack',
  'wrong Lambda hash', 'unknown Lambda archive',
]) {
  test(`a plan with ${scenario} requires a separate owner decision before mutation`, (t) => {
    const fixture = createReleaseFixture(t);
    const result = fixture.run('scripts/manual_production_deploy.sh', {
      ...fixture.environment,
      TEST_PLAN_SCENARIO: scenario,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Unsafe release plan/);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
  });
}

for (const [name, environment] of [
  ['missing credentials', { FAIL_RELEASE_STEP: 'aws sts get-caller-identity' }],
  ['an IAM user', { TEST_AWS_ARN: 'arn:aws:iam::111111111111:user/operator' }],
  ['a different assumed role', { TEST_AWS_ARN: 'arn:aws:sts::111111111111:assumed-role/admin/session' }],
  ['missing role configuration', { AWS_DEPLOY_ROLE_ARN: '' }],
  ['a missing region', { AWS_REGION: '' }],
  ['a different region', { AWS_REGION: 'us-east-1' }],
  ['conflicting region settings', { AWS_DEFAULT_REGION: 'us-east-1' }],
  ['credentials changed after plan', { TEST_CHANGED_IDENTITY: '1' }],
]) {
  test(`release identity rejects ${name}`, (t) => {
    const fixture = createReleaseFixture(t);
    const result = fixture.run('scripts/manual_production_deploy.sh', {
      ...fixture.environment, ...environment,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /credentials|identity|region|role/i);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
  });
}

for (const artifact of ['source', 'lambda', 'java', 'web', 'plan', 'evidence']) {
  test(`a ${artifact} mutation after preparation blocks saved-plan apply`, (t) => {
    const fixture = createReleaseFixture(t);
    const result = fixture.run('scripts/manual_production_deploy.sh', {
      ...fixture.environment,
      TEST_MUTATE_ARTIFACT: artifact,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /changed|mismatch/);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
  });
}

for (const artifact of ['lambda', 'web']) {
  test(`changing a checked ${artifact} during APK preparation cannot certify a new candidate`, (t) => {
    const fixture = createReleaseFixture(t);
    const result = fixture.run('scripts/manual_production_deploy.sh', {
      ...fixture.environment,
      TEST_MUTATE_CHECKED: artifact,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /changed/);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
  });
}

test('a held cross-host release lease prevents another checkout from publishing', (t) => {
  const fixture = createReleaseFixture(t);
  const held = {
    PK: { S: 'RELEASE#production' }, SK: { S: 'LEASE' }, owner: { S: 'other-host-release' },
  };
  fs.writeFileSync(fixture.environment.TEST_RELEASE_LEASE, JSON.stringify(held));
  const result = fixture.run('scripts/manual_production_deploy.sh', fixture.environment);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /lease|held/i);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
  assert.deepEqual(JSON.parse(fs.readFileSync(fixture.environment.TEST_RELEASE_LEASE)), held);
});

test('a failed apply retains release ownership until the owner resolves the partial failure', (t) => {
  const fixture = createReleaseFixture(t);
  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment, FAIL_RELEASE_STEP: 'terraform apply',
  });
  assert.notEqual(result.status, 0);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_LEASE), true);
  const successor = createReleaseFixture(t);
  const next = successor.run('scripts/manual_production_deploy.sh', {
    ...successor.environment, TEST_RELEASE_LEASE: fixture.environment.TEST_RELEASE_LEASE,
  });
  assert.notEqual(next.status, 0);
  assert.equal(fs.existsSync(successor.environment.TEST_RELEASE_INFRA), false);
});

test('a verified release conditionally relinquishes only its own lease', (t) => {
  const fixture = createReleaseFixture(t);
  const result = fixture.run('scripts/manual_production_deploy.sh', fixture.environment);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Release lease acquired/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_LEASE), false);
});

for (const state of ['old code', 'inactive']) {
  test(`a Lambda with ${state} cannot be certified by a healthy old API`, (t) => {
    const fixture = createReleaseFixture(t);
    const result = fixture.run('scripts/manual_production_deploy.sh', {
      ...fixture.environment, TEST_LIVE_LAMBDA: state,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Lambda.*candidate|Lambda.*ready/);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
    assert.doesNotMatch(result.stdout, /Completed Successfully/);
  });
}

for (const step of [
  'terraform init', 'terraform validate', 'terraform show', 'flutter test', 'flutter build apk',
  'java test', 'java lambdaZip',
  'aws s3 sync', 'aws cloudfront create-invalidation', 'aws cloudfront wait', 'curl health',
]) {
  test(`failure in ${step} leaves explicit failed release evidence, never verified success`, (t) => {
    const fixture = createReleaseFixture(t);
    const result = fixture.run('scripts/manual_production_deploy.sh', {
      ...fixture.environment, FAIL_RELEASE_STEP: step,
    });
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.stdout, /Completed Successfully/);
    const releases = path.join(fixture.root, 'dev_builds/releases');
    const directory = path.join(releases, fs.readdirSync(releases)[0]);
    const status = JSON.parse(fs.readFileSync(path.join(directory, 'status.json')));
    assert.equal(status.status, 'failed');
    assert.ok(status.phase);
    assert.notEqual(status.exitCode, 0);
    if (!step.startsWith('aws ') && step !== 'curl health') {
      assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
      assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
    }
  });
}

test('a candidate changed during infrastructure apply is never published', (t) => {
  const fixture = createReleaseFixture(t);
  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment, TEST_MUTATE_AFTER_APPLY: '1',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /artifact changed/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
});

test('the canonical readiness command cannot omit failing public release contracts', (t) => {
  const fixture = createReleaseFixture(t);
  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment, TEST_FAIL_RELEASE_CONTRACT: '1',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /public release contract failure/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
});

test('the protected workflow invokes the same public release command from its gated detached SHA', (t) => {
  const workflow = fs.readFileSync(path.join(sourceRoot, '.github/workflows/production-deploy.yml'), 'utf8');
  assert.match(workflow, /needs: readiness-gates/);
  assert.match(workflow, /name: production/);
  assert.match(workflow, /id-token: write/);
  assert.match(workflow, /aws-actions\/configure-aws-credentials@v4/);
  assert.match(workflow, /group: production-deployment\n  cancel-in-progress: false/);
  assert.equal((workflow.match(/if: github.ref == 'refs\/heads\/main' && inputs.confirm_production_deploy == 'yes'/g) || []).length, 2);
  assert.match(workflow, /PRODUCTION_DEPLOY_APPROVED: ['"]?YES/);
  const command = workflow.match(/run: (scripts\/manual_production_deploy\.sh)\s*$/m)?.[1];
  assert.ok(command, 'The workflow must use the guarded public entrypoint, not duplicate deployment stages');
  assert.doesNotMatch(workflow, /terraform apply|aws s3 sync|flutter build|build\.sh --check/);
  const fixture = createReleaseFixture(t);
  fixture.git('checkout', '--quiet', '--detach');
  const result = fixture.run(command, {
    ...fixture.environment, GITHUB_ACTIONS: 'true', GITHUB_REF: 'refs/heads/main',
    GITHUB_SHA: fixture.git('rev-parse', 'HEAD').trim(),
  });
  assert.equal(result.status, 0, result.stderr);
});

test('readiness CI covers stacked PR bases and includes public release contracts', () => {
  const workflow = fs.readFileSync(path.join(sourceRoot, '.github/workflows/ci.yml'), 'utf8');
  assert.match(workflow, /  pull_request:\s*\n\npermissions:/);
  assert.match(workflow, /run: scripts\/ci\/release-test/);
});

test('release browser readiness installs the pinned client only if missing, using system Chromium', (t) => {
  const fixture = createReleaseFixture(t);
  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment, TEST_PLAYWRIGHT_MISSING: '1',
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_NPM), true);
});

test('loss of release ownership after planning stops apply and never clears the new owner', (t) => {
  const fixture = createReleaseFixture(t);
  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment, TEST_MUTATE_ARTIFACT: 'lease',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /lease ownership changed/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
  assert.equal(JSON.parse(fs.readFileSync(fixture.environment.TEST_RELEASE_LEASE)).owner.S, 'replacement-owner');
});

test('a late ownership change cannot delete another release lease or report success', (t) => {
  const fixture = createReleaseFixture(t);
  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment, TEST_REPLACE_LEASE_AT_END: '1',
  });
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /Completed Successfully/);
  assert.equal(JSON.parse(fs.readFileSync(fixture.environment.TEST_RELEASE_LEASE)).owner.S, 'replacement-owner');
});

for (const [name, environment] of [
  ['disabled Terraform state locking', { TF_CLI_ARGS_apply: '-lock=false' }],
  ['an alternate Terraform workspace', { TF_WORKSPACE: 'test' }],
]) {
  test(`the release rejects ${name}`, (t) => {
    const fixture = createReleaseFixture(t);
    const result = fixture.run('scripts/manual_production_deploy.sh', {
      ...fixture.environment, ...environment,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Terraform.*configuration|Terraform.*workspace/);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
    assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_LEASE), false);
  });
}

test('artifact changes during live Lambda inspection cannot slip into publication', (t) => {
  const fixture = createReleaseFixture(t);
  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment, TEST_MUTATE_DURING_LIVE_CHECK: '1',
  });
  assert.notEqual(result.status, 0);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_CLOUD), false);
});

test('the public browser prerequisite command prepares CI without requiring or building an application', (t) => {
  const fixture = createReleaseFixture(t);
  const result = spawnSync(path.join(fixture.root, 'scripts/run-browser-e2e.sh'), ['--prepare'], {
    cwd: fixture.root, encoding: 'utf8',
    env: {
      ...process.env, ...fixture.environment, TEST_PLAYWRIGHT_MISSING: '1',
      PATH: `${fixture.bin}:${process.env.PATH}`,
    },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_NPM), true);
  assert.equal(fs.existsSync(path.join(fixture.root, 'frontend/build/web')), false);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_LEASE), false);
});

test('malformed private plan JSON fails without disclosing its contents in shared logs', (t) => {
  const fixture = createReleaseFixture(t);
  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment, TEST_PLAN_SCENARIO: 'malformed private JSON',
  });
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout + result.stderr, /private-plan-value/);
  assert.match(result.stderr, /Unsafe release plan.*JSON/);
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
});

test('a non-file web marker cannot redirect archival writes outside the candidate', (t) => {
  const fixture = createReleaseFixture(t);
  const target = path.join(fixture.temporary, 'protected-marker-target');
  fs.writeFileSync(target, 'must remain unchanged');
  const result = fixture.run('scripts/manual_production_deploy.sh', {
    ...fixture.environment, TEST_MARKER_TARGET: target,
  });
  assert.notEqual(result.status, 0);
  assert.equal(fs.readFileSync(target, 'utf8'), 'must remain unchanged');
  assert.equal(fs.existsSync(fixture.environment.TEST_RELEASE_INFRA), false);
});
