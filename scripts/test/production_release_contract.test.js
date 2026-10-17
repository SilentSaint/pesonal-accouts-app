const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
const deployScriptSource = path.join(root, 'scripts', 'deploy_and_build.sh');
const manualDeployScriptSource = path.join(root, 'scripts', 'manual_production_deploy.sh');

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
  fs.mkdirSync(path.join(fixture, 'scripts', 'ci'), { recursive: true });
  fs.mkdirSync(path.join(fixture, 'terraform'), { recursive: true });
  fs.mkdirSync(path.join(fixture, 'frontend'), { recursive: true });
  fs.copyFileSync(deployScriptSource, path.join(fixture, 'scripts', 'deploy_and_build.sh'));
  fs.chmodSync(path.join(fixture, 'scripts', 'deploy_and_build.sh'), 0o755);
  fs.copyFileSync(manualDeployScriptSource, path.join(fixture, 'scripts', 'manual_production_deploy.sh'));
  fs.chmodSync(path.join(fixture, 'scripts', 'manual_production_deploy.sh'), 0o755);

  writeExecutable(
    path.join(fixture, 'scripts', 'ci', 'verify-local-docker'),
    '#!/usr/bin/env bash\nprintf "verify-local-docker %s\\n" "$*" >> "$AET_TEST_LOG"\n',
  );

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
  *"rev-parse --verify"*)
    for arg in "$@"; do
      if [[ "$arg" == "PREVIOUS^{commit}" || "$arg" == "nonexistent-sha^{commit}" || "$arg" == "invalid-sha^{commit}" ]]; then
        exit 1
      fi
    done
    printf '%s\n' "\${ROLLBACK_TARGET_SHA:-release-sha}"
    ;;
  *"rev-parse HEAD")
    if [[ "$PWD" == *aet-rollback-worktree* || "$*" == *aet-rollback-worktree* ]]; then
      printf '%s\\n' "\${ROLLBACK_TARGET_SHA:-release-sha}"
    else
      printf '%s\\n' "\${AET_TEST_HEAD_SHA:-release-sha}"
    fi
    ;;
  *"rev-parse origin/main")
    printf '%s\\n' "\${AET_TEST_HEAD_SHA:-release-sha}"
    ;;
  *"merge-base --is-ancestor"*)
    ;;
  *"fetch"*)
    ;;
  *"status --porcelain"*)
    ;;
  *"worktree add"*)
    worktree_dir=""
    for arg in "$@"; do
      if [[ "$arg" == /tmp/* || "$arg" == *aet-rollback-worktree* ]]; then
        worktree_dir="$arg"
        break
      fi
    done
    if [[ -n "$worktree_dir" ]]; then
      mkdir -p "$worktree_dir/scripts" "$worktree_dir/terraform" "$worktree_dir/frontend"
      cp "$AET_TEST_FIXTURE_DIR/scripts/deploy_and_build.sh" "$worktree_dir/scripts/deploy_and_build.sh"
      cp -r "$AET_TEST_FIXTURE_DIR/backend" "$worktree_dir/backend"
    fi
    ;;
  *"worktree remove"*)
    ;;
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
      *:s3_web_bucket_name)
        if [[ "\${AET_TEST_TERRAFORM_NO_BUCKET:-0}" == 1 ]]; then
          printf 'unknown-output\\n'
        else
          printf 'web-bucket\\n'
        fi
        ;;
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
  printf '%s\\n' "\${AET_TEST_WEB_CONTENT:-web}" > build/web/index.html
elif [[ "\${1:-}" == build && "\${2:-}" == apk ]]; then
  mkdir -p build/app/outputs/flutter-apk
  printf '%s\\n' "\${AET_TEST_APK_CONTENT:-apk}" > build/app/outputs/flutter-apk/app-debug.apk
fi
`,
  );

  writeExecutable(
    path.join(bin, 'aws'),
    `#!/usr/bin/env bash
set -euo pipefail
printf 'aws %s\n' "$*" >> "$AET_TEST_LOG"
if [[ "\${1:-}" == sts ]]; then
  printf '727118420276\n'
elif [[ "\${1:-}" == s3 && "\${2:-}" == cp ]]; then
  if [[ "\${3:-}" == *terraform.tfstate* ]]; then
    if [[ "\${AET_TEST_STATE_S3_ERROR:-}" == "access-denied" || "\${AET_TEST_STATE_S3_ERROR:-}" == "AccessDenied" ]]; then
      echo 'fatal error: An error occurred (AccessDenied) when calling the GetObject operation: Access Denied' >&2
      exit 1
    elif [[ "\${AET_TEST_STATE_S3_ERROR:-}" == "404" ]]; then
      echo 'fatal error: An error occurred (404) when calling the GetObject operation: Key "production/terraform.tfstate" does not exist' >&2
      exit 1
    fi
  fi
  if [[ "\${AET_TEST_S3_CP_ERROR:-}" == "access-denied" ]]; then
    echo 'fatal error: An error occurred (AccessDenied) when calling the GetObject operation: Access Denied' >&2
    exit 1
  elif [[ "\${AET_TEST_S3_CP_ERROR:-}" == "network-error" ]]; then
    echo 'fatal error: Could not connect to the endpoint URL' >&2
    exit 1
  fi
  src="\${3:-}"
  dest="\${4:-}"
  s3_dir="\${AET_TEST_S3_DIR:-}"
  if [[ "$src" == s3://* && "$dest" == "-" ]]; then
    target_key="\${src##*/}"
    if [[ -n "$s3_dir" && -f "$s3_dir/$target_key" ]]; then
      cat "$s3_dir/$target_key"
    elif [[ "$target_key" == "last-verified-release.json" && -n "\${AET_TEST_VERIFIED_S3_MARKER:-}" ]]; then
      printf '%s\n' "$AET_TEST_VERIFIED_S3_MARKER"
    elif [[ -n "\${AET_TEST_EXISTING_S3_MARKER:-}" && "$target_key" != "last-verified-release.json" ]]; then
      printf '%s\n' "$AET_TEST_EXISTING_S3_MARKER"
    else
      echo "fatal error: An error occurred (404) when calling the GetObject operation: Key \"$target_key\" does not exist" >&2
      exit 1
    fi
  elif [[ "$dest" == s3://* ]]; then
    target_key="\${dest##*/}"
    if [[ -n "$s3_dir" ]]; then
      mkdir -p "$s3_dir"
      if [[ "$src" == "-" ]]; then
        cat > "$s3_dir/$target_key"
      else
        cp "$src" "$s3_dir/$target_key"
      fi
    fi
  fi
elif [[ "\${1:-}" == s3 && "\${2:-}" == sync ]]; then
  src="\${3:-}"
  dest="\${4:-}"
  s3_dir="\${AET_TEST_S3_DIR:-}"
  if [[ -n "$s3_dir" && -d "$src" ]]; then
    mkdir -p "$s3_dir"
    cp -r "$src"/* "$s3_dir/" 2>/dev/null || true
  fi
elif [[ "\${1:-}" == s3api && "\${2:-}" == list-buckets ]]; then
  if [[ "\${AET_TEST_LIST_BUCKETS_ERROR:-}" == "access-denied" || "\${AET_TEST_LIST_BUCKETS_ERROR:-}" == "AccessDenied" ]]; then
    echo 'fatal error: An error occurred (AccessDenied) when calling the ListBuckets operation: Access Denied' >&2
    exit 1
  fi
  if [[ "\${AET_TEST_LIST_BUCKETS_EMPTY:-0}" == 1 ]]; then
    printf 'None\n'
  else
    printf 'expense-tracker-web-727118420276\n'
  fi
elif [[ "\${1:-}" == cloudfront && "\${2:-}" == create-invalidation ]]; then
  printf 'invalidation-123\n'
fi
`,
  );

  writeExecutable(
    path.join(bin, 'curl'),
    `#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\n' "$*" >> "$AET_TEST_LOG"
if [[ "\${AET_TEST_FAIL_HEALTH:-0}" == 1 && "$*" == */api/health* ]]; then
  echo "500 Internal Server Error" >&2
  exit 22
fi
if [[ "$*" == *deployment-version.json* ]]; then
  if [[ -n "\${ROLLBACK_TARGET_SHA:-}" ]]; then
    printf '{"commit":"%s"}\n' "$ROLLBACK_TARGET_SHA"
  else
    printf '{"commit":"%s"}\n' "\${AET_TEST_HEAD_SHA:-release-sha}"
  fi
elif [[ "$*" == *release-metadata.json* ]]; then
  if [[ -n "\${ROLLBACK_TARGET_SHA:-}" ]]; then
    printf '{"current_commit":"%s"}\n' "$ROLLBACK_TARGET_SHA"
  else
    printf '{"current_commit":"%s"}\n' "\${AET_TEST_HEAD_SHA:-release-sha}"
  fi
else
  printf '{"status":"ok"}\n'
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

  const s3Dir = path.join(fixture, 's3_storage');
  fs.mkdirSync(s3Dir, { recursive: true });

  return { fixture, bin, log, planJson, s3Dir };
}

function runDeployment(fixture, overrides = {}) {
  const environment = {
    ...process.env,
    PATH: `${fixture.bin}:${process.env.PATH}`,
    AET_GUARDED_RELEASE: 'YES',
    AET_TEST_LOG: fixture.log,
    AET_TEST_PLAN_JSON: fixture.planJson,
    AET_TEST_S3_DIR: fixture.s3Dir,
    AWS_REGION: 'ap-south-2',
    AWS_ACCOUNT_ID: '727118420276',
    ...overrides,
  };

  return spawnSync(path.join(fixture.fixture, 'scripts', 'deploy_and_build.sh'), [], {
    cwd: fixture.fixture,
    env: environment,
    encoding: 'utf8',
  });
}

function runManualDeploy(fixture, overrides = {}) {
  const environment = {
    ...process.env,
    PATH: `${fixture.bin}:${process.env.PATH}`,
    PRODUCTION_DEPLOY_APPROVED: 'YES',
    AET_TEST_FIXTURE_DIR: fixture.fixture,
    AET_TEST_LOG: fixture.log,
    AET_TEST_PLAN_JSON: fixture.planJson,
    AET_TEST_S3_DIR: fixture.s3Dir,
    AWS_REGION: 'ap-south-2',
    AWS_ACCOUNT_ID: '727118420276',
    ...overrides,
  };

  return spawnSync(path.join(fixture.fixture, 'scripts', 'manual_production_deploy.sh'), [], {
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

test('refuses deployment when AWS_REGION does not match ap-south-2 even if EXPECTED_AWS_REGION is overridden', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, {
      AWS_REGION: 'us-east-1',
      EXPECTED_AWS_REGION: 'us-east-1',
    });
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, /AWS_REGION must be ap-south-2, got 'us-east-1'/);
  } finally {
    removeFixture(fixture);
  }
});

test('refuses deployment when AWS_REGION is empty', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, {
      AWS_REGION: '',
    });
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, /AWS_REGION is required/);
  } finally {
    removeFixture(fixture);
  }
});

test('refuses deployment when AWS_ACCOUNT_ID does not match 727118420276 even if EXPECTED_AWS_ACCOUNT_ID is overridden', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, {
      AWS_ACCOUNT_ID: '999999999999',
      EXPECTED_AWS_ACCOUNT_ID: '999999999999',
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /AWS_ACCOUNT_ID must be 727118420276, got '999999999999'/);
  } finally {
    removeFixture(fixture);
  }
});

test('refuses deployment when AWS_ACCOUNT_ID is empty', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, {
      AWS_ACCOUNT_ID: '',
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /AWS_ACCOUNT_ID is required/);
  } finally {
    removeFixture(fixture);
  }
});

test('rollback deployment cleanly replaces existing destination directory and file removing obsolete assets', () => {
  const fixture = createFixture();
  try {
    const existingWebDir = path.join(fixture.fixture, 'dev_builds', 'web-v1.0.1+2');
    fs.mkdirSync(existingWebDir, { recursive: true });
    fs.writeFileSync(path.join(existingWebDir, 'index.html'), 'stale-web-content\n');
    fs.writeFileSync(path.join(existingWebDir, 'obsolete-bundle-asset.js'), 'obsolete-code\n');

    const existingApkFile = path.join(fixture.fixture, 'dev_builds', 'app-v1.0.1+2-debug.apk');
    fs.writeFileSync(existingApkFile, 'stale-apk-content\n');

    const rollbackSha = 'rollback-sha-12345';
    const result = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: rollbackSha,
      AET_TEST_HEAD_SHA: rollbackSha,
      AET_TEST_WEB_CONTENT: 'rollback-web',
      AET_TEST_APK_CONTENT: 'rollback-apk',
    });

    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.match(result.stdout, /Rollback release deliverables preserved at .*\/dev_builds/);

    // Obsolete asset inside existing directory must disappear (clean replacement, no merge)
    assert.equal(
      fs.existsSync(path.join(existingWebDir, 'obsolete-bundle-asset.js')),
      false,
      'Obsolete files inside preserved directory should have been removed, not merged',
    );

    // Rollback web bundle content must replace stale index.html
    assert.equal(
      fs.readFileSync(path.join(existingWebDir, 'index.html'), 'utf8'),
      'rollback-web\n',
    );

    // Rollback APK must replace stale APK file
    assert.equal(
      fs.readFileSync(existingApkFile, 'utf8'),
      'rollback-apk\n',
    );
  } finally {
    removeFixture(fixture);
  }
});

test('persists current and previous release metadata rotating the deployed SHA into durable record', () => {
  const fixture = createFixture();
  try {
    // 1. Simulate forward deploy when previous release was deployed at known-good-sha-111
    const result = runDeployment(fixture, {
      AET_TEST_VERIFIED_S3_MARKER: '{"commit":"known-good-sha-111"}',
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);

    // Verify dev_builds/release-metadata.json was created and has both current and previous SHAs
    const metadataPath = path.join(fixture.fixture, 'dev_builds', 'release-metadata.json');
    assert.ok(fs.existsSync(metadataPath), 'dev_builds/release-metadata.json must exist');
    const metadata = JSON.parse(fs.readFileSync(metadataPath, 'utf8'));
    assert.equal(metadata.current_commit, 'release-sha');
    assert.equal(metadata.previous_commit, 'known-good-sha-111');
    assert.ok(metadata.deployed_at, 'deployed_at timestamp must be present');

    // Verify deployment-version.json also preserved the previous commit
    const markerPath = path.join(fixture.fixture, 'dev_builds', 'web-v1.0.1+2', 'deployment-version.json');
    assert.ok(fs.existsSync(markerPath), 'dev_builds/web-v1.0.1+2/deployment-version.json must exist');
    const marker = JSON.parse(fs.readFileSync(markerPath, 'utf8'));
    assert.equal(marker.commit, 'release-sha');
    assert.equal(marker.previous_commit, 'known-good-sha-111');

    // 2. Simulate rollback using ROLLBACK_TARGET_SHA=PREVIOUS
    const rollbackResult = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: 'PREVIOUS',
      AET_TEST_HEAD_SHA: 'known-good-sha-111',
    });
    assert.equal(rollbackResult.status, 0, `${rollbackResult.stdout}\n${rollbackResult.stderr}`);
    assert.match(rollbackResult.stdout, /Rollback release deliverables preserved at .*\/dev_builds/);
  } finally {
    removeFixture(fixture);
  }
});

test('same-revision retry retains existing previous_commit instead of overwriting with current revision', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, {
      AET_TEST_EXISTING_S3_MARKER: JSON.stringify({
        commit: 'release-sha',
        previous_commit: 'known-good-ancestor-sha',
      }),
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);

    const metadataPath = path.join(fixture.fixture, 'dev_builds', 'release-metadata.json');
    assert.ok(fs.existsSync(metadataPath));
    const metadata = JSON.parse(fs.readFileSync(metadataPath, 'utf8'));
    assert.equal(metadata.current_commit, 'release-sha');
    assert.equal(
      metadata.previous_commit,
      'known-good-ancestor-sha',
      'Retry of release-sha must retain original previous_commit rather than overwriting with release-sha',
    );

    const markerPath = path.join(fixture.fixture, 'dev_builds', 'web-v1.0.1+2', 'deployment-version.json');
    const marker = JSON.parse(fs.readFileSync(markerPath, 'utf8'));
    assert.equal(marker.commit, 'release-sha');
    assert.equal(marker.previous_commit, 'known-good-ancestor-sha');
  } finally {
    removeFixture(fixture);
  }
});

test('refuses deployment when live deployment marker cannot be read from S3 due to permission or network failure', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, {
      AET_TEST_S3_CP_ERROR: 'access-denied',
    });
    const events = fs.readFileSync(fixture.log, 'utf8');

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Refusing deployment: failed to read .* marker/);
    assert.match(result.stderr, /AccessDenied/);
    assert.doesNotMatch(events, /flutter build web/);
    assert.doesNotMatch(events, /terraform .* apply/);
  } finally {
    removeFixture(fixture);
  }
});

test('preserves last verified release when a subsequent deployment fails live verification', () => {
  const fixture = createFixture();
  try {
    // 1. Release A deploys and passes verification
    const releaseA = 'verified-sha-aaa111';
    const resultA = runDeployment(fixture, {
      AET_TEST_HEAD_SHA: releaseA,
    });
    assert.equal(resultA.status, 0, `${resultA.stdout}\n${resultA.stderr}`);

    // Durable verified marker must exist in S3 for release A
    const verifiedMarkerFile = path.join(fixture.s3Dir, 'last-verified-release.json');
    assert.ok(fs.existsSync(verifiedMarkerFile), 'last-verified-release.json must be published to S3');
    const verifiedA = JSON.parse(fs.readFileSync(verifiedMarkerFile, 'utf8'));
    assert.equal(verifiedA.commit, releaseA);

    // 2. Release B builds, applies, publishes, but FAILS live health verification
    const releaseB = 'failed-sha-bbb222';
    const resultB = runDeployment(fixture, {
      AET_TEST_HEAD_SHA: releaseB,
      AET_TEST_FAIL_HEALTH: '1',
    });
    assert.notEqual(resultB.status, 0);

    // S3 verified marker must NOT have promoted failed release B; must still point to verified release A
    const verifiedAfterFail = JSON.parse(fs.readFileSync(verifiedMarkerFile, 'utf8'));
    assert.equal(
      verifiedAfterFail.commit,
      releaseA,
      'Failed release B must not overwrite verified release A in last-verified-release.json',
    );

    // 3. Subsequent release C deploys. It must adopt verified release A as previous_commit, NOT failed release B
    const releaseC = 'next-sha-ccc333';
    const resultC = runDeployment(fixture, {
      AET_TEST_HEAD_SHA: releaseC,
    });
    assert.equal(resultC.status, 0, `${resultC.stdout}\n${resultC.stderr}`);

    const metadataPath = path.join(fixture.fixture, 'dev_builds', 'release-metadata.json');
    const metadataC = JSON.parse(fs.readFileSync(metadataPath, 'utf8'));
    assert.equal(metadataC.current_commit, releaseC);
    assert.equal(
      metadataC.previous_commit,
      releaseA,
      'Release C must adopt last verified release A as previous_commit, not unverified release B',
    );
  } finally {
    removeFixture(fixture);
  }
});

test('refuses deployment when live deployment marker is malformed or missing commit SHA', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, {
      AET_TEST_EXISTING_S3_MARKER: '{"commit":""}',
    });
    const events = fs.readFileSync(fixture.log, 'utf8');

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /malformed or missing a valid commit SHA/);
    assert.doesNotMatch(events, /flutter build web/);
    assert.doesNotMatch(events, /terraform .* apply/);
  } finally {
    removeFixture(fixture);
  }
});

test('accepts valid deployment marker formatted with whitespace around colons', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, {
      AET_TEST_VERIFIED_S3_MARKER: '{\n  "commit": "valid-sha-1111111",\n  "previous_commit": "ancestor-sha-0000000"\n}',
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);

    const metadataPath = path.join(fixture.fixture, 'dev_builds', 'release-metadata.json');
    const metadata = JSON.parse(fs.readFileSync(metadataPath, 'utf8'));
    assert.equal(metadata.current_commit, 'release-sha');
    assert.equal(metadata.previous_commit, 'valid-sha-1111111');
  } finally {
    removeFixture(fixture);
  }
});

test('manual deploy resolves PREVIOUS from durable S3 metadata when local dev_builds is absent', () => {
  const fixture = createFixture();
  try {
    // Ensure dev_builds directory does not exist locally (simulating fresh release host)
    fs.rmSync(path.join(fixture.fixture, 'dev_builds'), { recursive: true, force: true });

    // Seed durable verified release in S3
    const remoteKnownGood = 'remote-known-good-sha-999';
    fs.writeFileSync(
      path.join(fixture.s3Dir, 'last-verified-release.json'),
      JSON.stringify({
        commit: 'current-sha-888',
        previous_commit: remoteKnownGood,
      }),
    );

    const result = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: 'PREVIOUS',
      AET_TEST_HEAD_SHA: remoteKnownGood,
    });

    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.match(result.stdout, /Rollback release deliverables preserved at .*\/dev_builds/);
  } finally {
    removeFixture(fixture);
  }
});

test('manual deploy rolls back failed live release directly to last verified commit', () => {
  const fixture = createFixture();
  try {
    const verifiedSha = 'verified-sha-aaa111';
    const olderSha = 'older-sha-zzz000';
    const failedLiveSha = 'failed-live-sha-bbb222';

    // Seed durable verified release in S3 pointing to verifiedSha
    fs.writeFileSync(
      path.join(fixture.s3Dir, 'last-verified-release.json'),
      JSON.stringify({
        commit: verifiedSha,
        previous_commit: olderSha,
      }),
    );

    // Seed live marker in S3 with failed unverified release
    fs.writeFileSync(
      path.join(fixture.s3Dir, 'deployment-version.json'),
      JSON.stringify({
        commit: failedLiveSha,
        previous_commit: verifiedSha,
      }),
    );

    // Operator triggers ROLLBACK_TARGET_SHA=PREVIOUS on failed release
    // It should target verifiedSha (the last known-good verified release), NOT olderSha
    const result = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: 'PREVIOUS',
      AET_TEST_HEAD_SHA: verifiedSha,
    });

    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.match(result.stdout, new RegExp(`All manual deployment guards passed for ${verifiedSha}`));
  } finally {
    removeFixture(fixture);
  }
});

test('manual deploy prefers durable S3 metadata over stale local dev_builds cache', () => {
  const fixture = createFixture();
  try {
    // 1. Create stale local dev_builds metadata
    const staleLocalDir = path.join(fixture.fixture, 'dev_builds');
    fs.mkdirSync(staleLocalDir, { recursive: true });
    fs.writeFileSync(
      path.join(staleLocalDir, 'last-verified-release.json'),
      JSON.stringify({
        commit: 'stale-sha-111',
        previous_commit: 'obsolete-sha-000',
      }),
    );

    // 2. Durable S3 metadata has fresh verified release
    const durableVerified = 'durable-live-sha-222';
    const durablePrev = 'remote-known-good-sha-333';
    fs.writeFileSync(
      path.join(fixture.s3Dir, 'last-verified-release.json'),
      JSON.stringify({
        commit: durableVerified,
        previous_commit: durablePrev,
      }),
    );
    fs.writeFileSync(
      path.join(fixture.s3Dir, 'deployment-version.json'),
      JSON.stringify({
        commit: durableVerified,
        previous_commit: durablePrev,
      }),
    );

    const result = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: 'PREVIOUS',
      AET_TEST_HEAD_SHA: durablePrev,
    });

    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    assert.match(result.stdout, new RegExp(`All manual deployment guards passed for ${durablePrev}`));
  } finally {
    removeFixture(fixture);
  }
});

test('manual deploy fails closed when durable S3 metadata read fails due to permission or network failure', () => {
  const fixture = createFixture();
  try {
    const result = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: 'PREVIOUS',
      AET_TEST_S3_CP_ERROR: 'access-denied',
    });
    const events = fs.readFileSync(fixture.log, 'utf8');

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Refusing rollback deployment: failed to read .* release metadata/);
    assert.match(result.stderr, /AccessDenied/);
    assert.doesNotMatch(events, /git worktree add/);
    assert.doesNotMatch(events, /deploy_and_build\.sh/);
  } finally {
    removeFixture(fixture);
  }
});

test('rollback deployment keeps rejected release out of the rollback pointer', () => {
  const fixture = createFixture();
  try {
    const releaseA = 'verified-sha-aaa111';
    const buggyReleaseB = 'buggy-sha-bbb222';

    // 1. Release A deploys and passes verification
    const resultA = runDeployment(fixture, {
      AET_TEST_HEAD_SHA: releaseA,
    });
    assert.equal(resultA.status, 0, `${resultA.stdout}\n${resultA.stderr}`);

    // 2. Release B deploys over A and passes verification
    const resultB = runDeployment(fixture, {
      AET_TEST_HEAD_SHA: buggyReleaseB,
    });
    assert.equal(resultB.status, 0, `${resultB.stdout}\n${resultB.stderr}`);

    // Verify S3 marker now records buggyReleaseB as commit and releaseA as previous_commit
    const s3VerifiedPath = path.join(fixture.s3Dir, 'last-verified-release.json');
    const markerB = JSON.parse(fs.readFileSync(s3VerifiedPath, 'utf8'));
    assert.equal(markerB.commit, buggyReleaseB);
    assert.equal(markerB.previous_commit, releaseA);

    // 3. Owner triggers rollback of buggyReleaseB to releaseA
    const rollbackResult = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: releaseA,
      AET_TEST_HEAD_SHA: releaseA,
    });
    assert.equal(rollbackResult.status, 0, `${rollbackResult.stdout}\n${rollbackResult.stderr}`);

    // Verify that after rollback to releaseA, the rollback pointer DOES NOT point to buggyReleaseB
    // and DOES NOT invent a Git parent when release history identifies no previous verified commit
    const markerAfterRollback = JSON.parse(fs.readFileSync(s3VerifiedPath, 'utf8'));
    assert.equal(markerAfterRollback.commit, releaseA);
    assert.notEqual(
      markerAfterRollback.previous_commit,
      buggyReleaseB,
      'Rollback deployment must not rotate the rejected release B into previous_commit',
    );
    assert.equal(
      markerAfterRollback.previous_commit,
      undefined,
      'Rollback deployment must not derive previous_commit from Git ancestry when release history identifies no previous verified commit',
    );

    const localMetaPath = path.join(fixture.fixture, 'dev_builds', 'release-metadata.json');
    const localMeta = JSON.parse(fs.readFileSync(localMetaPath, 'utf8'));
    assert.equal(localMeta.current_commit, releaseA);
    assert.notEqual(
      localMeta.previous_commit,
      buggyReleaseB,
      'Local release metadata must not rotate rejected release B into previous_commit',
    );
    assert.equal(
      localMeta.previous_commit,
      undefined,
      'Local release metadata must omit previous_commit when release history identifies no previous verified commit',
    );
  } finally {
    removeFixture(fixture);
  }
});

test('forward release adopts bootstrap rollback pointer when live marker represents an unverified publication', () => {
  const fixture = createFixture();
  try {
    const knownGoodA = 'verified-sha-aaa111';
    const unverifiedB = 'unverified-sha-bbb222';
    const releaseC = 'next-sha-ccc333';

    // S3 has NO last-verified-release.json (initial bootstrap state)
    // Live deployment-version.json has unverifiedB building on knownGoodA
    fs.writeFileSync(
      path.join(fixture.s3Dir, 'deployment-version.json'),
      JSON.stringify({
        commit: unverifiedB,
        previous_commit: knownGoodA,
      }),
    );

    // Forward release C deploys
    const resultC = runDeployment(fixture, {
      AET_TEST_HEAD_SHA: releaseC,
    });
    assert.equal(resultC.status, 0, `${resultC.stdout}\n${resultC.stderr}`);

    const s3VerifiedPath = path.join(fixture.s3Dir, 'last-verified-release.json');
    const markerC = JSON.parse(fs.readFileSync(s3VerifiedPath, 'utf8'));
    assert.equal(markerC.commit, releaseC);
    assert.equal(
      markerC.previous_commit,
      knownGoodA,
      'Release C must adopt bootstrap unverified marker previous_commit A rather than unverified B',
    );
  } finally {
    removeFixture(fixture);
  }
});

test('manual deploy fails closed when remote terraform state read fails during rollback bucket discovery', () => {
  const fixture = createFixture();
  try {
    const result = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: 'PREVIOUS',
      AET_TEST_TERRAFORM_NO_BUCKET: '1',
      AET_TEST_STATE_S3_ERROR: 'AccessDenied',
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Refusing rollback deployment: failed to read remote terraform state/);
  } finally {
    removeFixture(fixture);
  }
});

test('manual deploy fails closed when s3api list-buckets fails during rollback bucket discovery', () => {
  const fixture = createFixture();
  try {
    const result = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: 'PREVIOUS',
      AET_TEST_TERRAFORM_NO_BUCKET: '1',
      AET_TEST_STATE_S3_ERROR: '404',
      AET_TEST_LIST_BUCKETS_ERROR: 'AccessDenied',
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Refusing rollback deployment: failed to list S3 buckets for discovery/);
  } finally {
    removeFixture(fixture);
  }
});

test('manual deploy fails closed when rollback bucket cannot be discovered and refuses fallback to web-bucket', () => {
  const fixture = createFixture();
  try {
    const result = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: 'PREVIOUS',
      AET_TEST_TERRAFORM_NO_BUCKET: '1',
      AET_TEST_STATE_S3_ERROR: '404',
      AET_TEST_LIST_BUCKETS_EMPTY: '1',
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /could not discover web bucket/);
  } finally {
    removeFixture(fixture);
  }
});

test('refuses deployment when marker contains malformed previous_commit', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, {
      AET_TEST_EXISTING_S3_MARKER: '{"commit":"valid-commit-1111111","previous_commit":"bad\\"quote"}',
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /malformed previous_commit/);
  } finally {
    removeFixture(fixture);
  }
});

test('refuses deployment when marker previous_commit is not a valid commit in the repository', () => {
  const fixture = createFixture();
  try {
    const result = runDeployment(fixture, {
      AET_TEST_EXISTING_S3_MARKER: '{"commit":"valid-commit-1111111","previous_commit":"nonexistent-sha"}',
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /invalid previous_commit/);
  } finally {
    removeFixture(fixture);
  }
});

test('forward release omits rollback pointer when live marker represents an unverified bootstrap publication without predecessor', () => {
  const fixture = createFixture();
  try {
    const unverifiedB = 'unverified-sha-bbb222';
    const releaseC = 'next-sha-ccc333';

    // S3 has NO last-verified-release.json
    // Live deployment-version.json has unverifiedB WITHOUT previous_commit
    fs.writeFileSync(
      path.join(fixture.s3Dir, 'deployment-version.json'),
      JSON.stringify({
        commit: unverifiedB,
      }),
    );

    // Forward release C deploys
    const resultC = runDeployment(fixture, {
      AET_TEST_HEAD_SHA: releaseC,
    });
    assert.equal(resultC.status, 0, `${resultC.stdout}\n${resultC.stderr}`);

    const s3VerifiedPath = path.join(fixture.s3Dir, 'last-verified-release.json');
    const markerC = JSON.parse(fs.readFileSync(s3VerifiedPath, 'utf8'));
    assert.equal(markerC.commit, releaseC);
    assert.equal(
      markerC.previous_commit,
      undefined,
      'Release C must omit previous_commit when live unverified marker has no verified predecessor',
    );
  } finally {
    removeFixture(fixture);
  }
});

test('manual deploy fails closed when verified rollback marker lacks valid commit SHA', () => {
  const fixture = createFixture();
  try {
    // Verified marker in S3 has empty commit but plausible previous_commit
    fs.writeFileSync(
      path.join(fixture.s3Dir, 'last-verified-release.json'),
      JSON.stringify({
        commit: '',
        previous_commit: 'valid-ancestor-sha',
      }),
    );

    const result = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: 'PREVIOUS',
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Refusing rollback deployment: verified release marker .* is malformed or missing a valid commit SHA/);
  } finally {
    removeFixture(fixture);
  }
});

test('manual deploy fails closed when verified rollback marker has malformed previous_commit', () => {
  const fixture = createFixture();
  try {
    fs.writeFileSync(
      path.join(fixture.s3Dir, 'last-verified-release.json'),
      JSON.stringify({
        commit: 'valid-sha-1111111',
        previous_commit: 'bad"quote',
      }),
    );

    const result = runManualDeploy(fixture, {
      ROLLBACK_TARGET_SHA: 'PREVIOUS',
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Refusing rollback deployment: verified release marker .* contains malformed previous_commit/);
  } finally {
    removeFixture(fixture);
  }
});



