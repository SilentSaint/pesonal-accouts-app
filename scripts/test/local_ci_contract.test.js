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

function workflowStepScript(workflow, stepName, nextJobName) {
  const stepStart = workflow.indexOf(`      - name: ${stepName}\n`);
  assert.notEqual(stepStart, -1, `workflow step ${stepName} must exist`);
  const stepEnd = workflow.indexOf(`\n  ${nextJobName}:`, stepStart);
  assert.notEqual(stepEnd, -1, `workflow job ${nextJobName} must follow ${stepName}`);
  const step = workflow.slice(stepStart, stepEnd);
  const run = step.match(/^        run: (.*)$/m);
  assert.ok(run, `${stepName} must define a run command`);
  if (run[1] !== '|') return run[1];

  const bodyStart = step.indexOf(run[0]) + run[0].length + 1;
  const body = [];
  for (const line of step.slice(bodyStart).split('\n')) {
    if (line.trim() === '') {
      body.push('');
      continue;
    }
    if (!line.startsWith('          ')) break;
    body.push(line.slice(10));
  }
  return body.join('\n').replace(/\n+$/, '');
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

test('Codex PR review automation stays bound to the reviewed current head', () => {
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
    'the canonical Codex review wording must remain documented',
  );
  assert.match(workflow, /valid current-head Codex\s+approval/);
  assert.match(workflow, /all review\s+conversations are resolved before merge/i);
  assert.doesNotMatch(workflow, /no actionable\s+review conversations remain unresolved/i);
  assert.match(workflow, /full local\s+Docker gate passes on the exact current head/);
  assert.match(workflow, /Track the base branch\s+SHA alongside the reviewed head SHA/i);
});

test('Codex review comments accept clear equivalent approval wording for the reviewed head', () => {
  const workflow = read('docs/engineering/workflow.md');

  assert.match(workflow, /classify the complete Codex review comment by meaning, not exact wording/i);
  assert.match(workflow, /author is the configured Codex review bot/i);
  assert.match(workflow, /explicitly state\s+no major issues or an equivalent unambiguous\s+approval/i);
  assert.match(workflow, /Nice work!/);
  assert.match(workflow, /LGTM|Looks good to me/);
  assert.match(workflow, /praise alone is not/i);
  assert.match(workflow, /actionable findings, requests\s+for changes, caveats, conditional approval, or mixed feedback are not an\s+approval/i);
  assert.match(workflow, /reviewed head SHA.*current PR head/is);
  assert.match(workflow, /review record unambiguously associated with that comment/i);
  assert.match(workflow, /missing\/ambiguous SHA[\s\S]*invalidates the signal/i);
  assert.match(workflow, /any new commit after that\s+review.*invalidates the signal/is);
});

test('the canonical workflow is the sole source of conditional agent merge authority', () => {
  const agents = read('AGENTS.md');
  const workflow = read('docs/engineering/workflow.md');

  assert.match(
    agents,
    /GitHub repository `SilentSaint\/pesonal-accouts-app` as\s+the\s+canonical integration surface/i,
  );
  assert.match(agents, /GitHub read\/write and pull-request operations/i);
  assert.match(agents, /canonical engineering workflow\]\(docs\/engineering\/workflow\.md#pull-requests-and-merge\)/i);
  assert.doesNotMatch(agents, /AWS CodeCommit repository in `ap-south-2` as the\s+canonical integration surface/i);
  assert.doesNotMatch(agents, /required CodeCommit read\/write and pull-request operations/i);
  assert.match(agents, /Merge authority\*\*:\s*follow the \[canonical engineering workflow\]/i);
  assert.doesNotMatch(agents, /owner grants standing authorization for the agent to merge/i);
  assert.doesNotMatch(agents, /codex-approval Actions status is a required merge-authorization policy gate/i);
  assert.match(workflow, /owner grants standing authorization for the agent to merge/i);
  assert.match(workflow, /qualifying current-head Codex approval and every merge gate below pass/i);
  assert.doesNotMatch(agents, /only the repository owner reviews and merges/i);
  assert.doesNotMatch(
    agents,
    /Automated Codex and local\s+Standards\/Spec reviews are advisory inputs only and never authorize agents to merge/i,
  );
  assert.doesNotMatch(workflow, /only the owner merges through the pull-request path/i);
  assert.doesNotMatch(workflow, /review approval is not merge authorization for an agent/i);
});

test('mutable Codex signals require server-enforced authorization at merge time', () => {
  const workflow = read('docs/engineering/workflow.md');

  assert.match(
    workflow,
    /treat a Codex comment or reaction as evidence only, not merge-time\s+authorization/i,
  );
  assert.match(
    workflow,
    /active server-side required status\s+check or native approval[\s\S]*bound to the exact verified `expected_head_sha`/i,
  );
  assert.match(
    workflow,
    /must invalidate authorization when a new negative Codex response\s+arrives or the qualifying signal is withdrawn/i,
  );
  assert.match(
    workflow,
    /required head-bound authorization gate or its enforcement cannot be verified[\s\S]*leave the PR unmerged/i,
  );
});

test('merge gate fails closed on incomplete review or validation evidence', () => {
  const workflow = read('docs/engineering/workflow.md');

  assert.match(workflow, /all review\s+conversations are resolved before merge/i);
  assert.doesNotMatch(workflow, /no actionable\s+review conversations remain unresolved/i);
  assert.match(workflow, /the PR is mergeable/i);
  assert.match(
    workflow,
    /full local\s+Docker gate passes on the exact current head without AWS credentials or\s+production mutations/i,
  );
  assert.match(workflow, /all required checks are acceptable/i);
  assert.match(workflow, /codexReconciliationSucceeded=false/i);
  assert.match(workflow, /failed\s+target-selection\/reconcile job, missing or unassociated workflow run/i);
  assert.match(workflow, /any configured\s+maintainer-approval requirement is satisfied/i);
  assert.match(workflow, /missing,\s+failing, or stale required check fails closed/i);
  assert.match(
    workflow,
    /head,\s+base,\s+ancestry, or any gate evidence differs,\s+invalidate the\s+prior approval and gate\s+results and require the branch to be\s+updated\/rebased and fresh review and\s+validation/i,
  );
  assert.match(workflow, /re-fetch the PR and the current `main` ref/i);
  assert.match(
    workflow,
    /record\s+the verified current `expected_head_sha`,\s+the PR `base_sha`, and the current\s+`main` SHA/i,
  );
  assert.match(workflow, /require the PR base to equal the current `main` SHA/i);
  assert.match(workflow, /verify\s+the\s+current `main` SHA is an ancestor of the PR head/i);
  assert.match(workflow, /base equality check alone\s+is\s+insufficient/i);
  assert.match(
    workflow,
    /active strict server-side\s+(?:up-to-date )?branch-protection(?:\/ruleset)? gate enforced for the authenticated\s+connector identity[\s\S]*?a merge queue, or a repository-wide\s+serialization lock/i,
  );
  assert.match(workflow, /up-to-date branch-protection\/ruleset gate enforced for the authenticated\s+connector identity/i);
  assert.match(workflow, /no administrator\/custom-role\/bypass-app exemption/i);
  assert.match(workflow, /strict gate that the connector identity can bypass\s+does not qualify/i);
  assert.match(workflow, /if enforcement for that identity cannot be verified, use the\s+queue\/serialization-lock path or leave the PR unmerged and hand it to the\s+owner/i);
  assert.match(workflow, /covers this final\s+refresh through merge/i);
  assert.match(workflow, /callable\s+head guard alone does not serialize\s+`main`/i);
  assert.match(workflow, /if no such\s+active gate is present,\s+leave the PR unmerged and hand it to the owner/i);
  assert.match(workflow, /ambiguous or incomplete\s+evidence leaves the PR unmerged and is handed to the owner/i);
});

test('review conversation resolution stays enforced through the merge operation', () => {
  const workflow = read('docs/engineering/workflow.md');

  assert.match(
    workflow,
    /server-side conversation-resolution enforcement for\s+the authenticated merge identity through the merge operation/i,
  );
  assert.match(
    workflow,
    /active\s+ruleset\/branch-protection rule must require all review conversations to be\s+resolved/i,
  );
  assert.match(workflow, /connector identity must not bypass it/i);
  assert.match(
    workflow,
    /a final thread\s+snapshot or a repository-wide serialization lock alone is insufficient/i,
  );
  assert.match(
    workflow,
    /intentionally\s+stricter than the issue's actionable-thread minimum[\s\S]*all threads, including non-actionable\s+ones/i,
  );
  assert.match(workflow, /if\s+enforcement is missing or unverifiable, leave the PR unmerged/i);
});

test('GitHub is consistently named as the canonical collaboration surface', () => {
  const agents = read('AGENTS.md');

  assert.match(agents, /^## GitHub Agent Collaboration Workflow$/m);
  assert.doesNotMatch(agents, /^## AWS Agent Collaboration Workflow$/m);
});

test('authorized merge routes by serialization mechanism and verifies the merged SHA', () => {
  const workflow = read('docs/engineering/workflow.md');

  assert.match(
    workflow,
    /strict branch-protection\/ruleset gate or repository-wide serialization\s+lock, invoke the GitHub connector's\s+`github_merge_pull_request` operation with\s+the verified `expected_head_sha`/i,
  );
  assert.match(workflow, /for a merge queue, use a queue-capable\s+asynchronous\/enqueue operation with that verified head instead/i);
  assert.match(workflow, /never call\s+the ordinary merge endpoint as a queue fallback/i);
  assert.match(workflow, /Treat an `enqueued` result as\s+pending rather than as a merged SHA/i);
  assert.match(workflow, /Only\s+after the queue reports\s+the actual merge/i);
  assert.match(workflow, /no queue-capable operation, or enqueue fails, is cancelled,\s+times out, or cannot be verified as merged, leave the PR unmerged and hand it\s+to the owner/i);
  assert.match(workflow, /Never write directly to `main`, enable auto-merge as a shortcut, or\s+deploy\/mutate AWS/i);
  assert.match(workflow, /verify the\s+returned\/eventual merged SHA and the resulting PR\/ref state read-only/i);
});

test('merge queue completion gates the exact merge-group revision', () => {
  const workflow = read('docs/engineering/workflow.md');

  assert.match(workflow, /before queue completion,\s+re-fetch the\s+PR's current head and verify its Codex authorization remains valid/i);
  assert.match(workflow, /verify\s+the current merge-group SHA and tree/i);
  assert.match(
    workflow,
    /full local Docker gate and required checks on that exact merge-group\s+SHA or a\s+verified identical tree/i,
  );
  assert.match(workflow, /Codex authorization remains bound to the exact current\s+PR head through queue completion/i);
  assert.match(workflow, /a new PR commit invalidates that authorization\s+even if its tree is identical/i);
  assert.match(
    workflow,
    /queue's server-side rules must block\s+completion\s+until both current PR-head authorization and merge-group validation\s+and checks pass/i,
  );
  assert.match(workflow, /merge-group SHA\s+or tree change invalidates validation/i);
  assert.match(workflow, /A PR head change invalidates authorization[\s\S]*a merge-group SHA\s+or tree change invalidates validation/i);
  assert.match(
    workflow,
    /PR head, merge-group revision, or its gates cannot be verified[\s\S]*leave the PR unmerged and hand it to the owner/i,
  );
});

test('Codex PR reactions are correlated to one tracked review request and head', () => {
  const workflow = read('docs/engineering/workflow.md');

  assert.match(workflow, /record\s+the request timestamp and full head SHA/i);
  assert.match(workflow, /associate it with exactly one recorded\s+review request/i);
  assert.match(workflow, /on the PR itself and comes from the configured Codex review bot/i);
  assert.match(workflow, /reaction timestamp must be after the recorded request/i);
  assert.match(workflow, /current PR head must still match the tracked head/i);
  assert.match(workflow, /multiple possible\s+requests or any head change make the association ambiguous/i);
  assert.match(workflow, /Reactions on review comments, reactions from the\s+owner\/other actors.*do not satisfy this gate/is);
});

test('the selector skips cleanly until trusted main has the approval policy script', () => {
  const action = read('.github/workflows/codex-approval-status.yml');
  const workflow = read('docs/engineering/workflow.md');
  const selectorScript = workflowStepScript(
    action,
    'Select PRs for independent reconciliation',
    'reconcile',
  );
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-policy-bootstrap-'));
  const outputFile = path.join(tempRoot, 'github-output');

  try {
    const result = spawnSync('bash', ['--noprofile', '--norc', '-e', '-c', selectorScript], {
      cwd: tempRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        GITHUB_OUTPUT: outputFile,
        PATH: `${path.dirname(process.execPath)}:${process.env.PATH || ''}`,
      },
    });

    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(outputFile, 'utf8'), 'pr_targets=[]\n');
    assert.match(
      action,
      /if:\s*\$\{\{\s*needs\.select-pull-requests\.outputs\.pr_targets\s*!=\s*''\s*&&\s*needs\.select-pull-requests\.outputs\.pr_targets\s*!=\s*'\[\]'\s*\}\}/,
    );
    assert.match(
      workflow,
      /bootstrap no-op does not publish\s+`codex-approval` and does not satisfy `codexReconciliationSucceeded`/i,
    );
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('the Codex approval status bridge is least-privilege and never executes PR code', () => {
  const action = read('.github/workflows/codex-approval-status.yml');
  const bridge = read('scripts/ci/codex-approval-status.js');
  const workflow = read('docs/engineering/workflow.md');

  assert.match(action, /issue_comment:/);
  assert.match(action, /pull_request_target:/);
  assert.match(action, /pull_request_review:/);
  assert.match(action, /pull_request_review_comment:/);
  assert.match(action, /schedule:/);
  assert.match(action, /select-pull-requests:/);
  assert.match(action, /--select-pr-targets/);
  assert.match(action, /pr_targets:\s*\$\{\{\s*steps\.select\.outputs\.pr_targets\s*\}\}/);
  assert.match(action, /matrix:[\s\S]*target:\s*\$\{\{\s*fromJSON\(needs\.select-pull-requests\.outputs\.pr_targets\)\s*\}\}/);
  assert.match(action, /group:\s*codex-approval-\$\{\{\s*github\.repository\s*\}\}-\$\{\{\s*matrix\.target\.number\s*\}\}/);
  assert.match(action, /CODEX_PR_NUMBER:\s*\$\{\{\s*matrix\.target\.number\s*\}\}/);
  assert.match(action, /CODEX_PR_HEAD_SHA:\s*\$\{\{\s*matrix\.target\.head_sha\s*\}\}/);
  assert.doesNotMatch(action, /group:\s*codex-approval-reconcile/);
  assert.match(action, /contents:\s*read/);
  assert.match(action, /issues:\s*read/);
  assert.match(action, /pull-requests:\s*read/);
  assert.match(action, /statuses:\s*write/);
  assert.match(action, /actions\/checkout@[a-f0-9]{40}/);
  assert.match(action, /ref:\s*refs\/heads\/main/);
  assert.match(action, /scripts\/ci\/codex-approval-status\.js/);
  assert.doesNotMatch(action, /head\.sha.*ref:|pull_request\.head\.ref/);
  assert.doesNotMatch(action, /npm (?:install|ci)|bash .*\.sh/);

  assert.match(bridge, /const STATUS_CONTEXT = 'codex-approval'/);
  assert.match(bridge, /statuses\/\$\{sha\}/);
  assert.match(bridge, /query PullRequestApprovalReviews/);
  assert.match(bridge, /lastEditedAt/);
  assert.match(bridge, /updatedAt/);
  assert.match(bridge, /updated_at:\s*review\.lastEditedAt\s*\|\|\s*review\.updatedAt\s*\|\|\s*review\.submittedAt/);
  assert.match(bridge, /await publish\('pending'/);
  assert.match(bridge, /await publish\('error'/);
  assert.match(bridge, /DELETED_FEEDBACK_DESCRIPTION/);
  assert.match(bridge, /latestDeletedFeedbackRevocation/);
  assert.match(bridge, /revokedAt/);
  assert.match(bridge, /allowedRequesters: \[repository\.owner\]/);
  assert.match(bridge, /sameLogin\(status\.creator\.login, 'github-actions\[bot\]'\)/);
  assert.match(workflow, /machine-readable marker[\s\S]*codex-review-request: head=<40-character-head-sha>/i);
  assert.match(workflow, /`codex-approval` commit status on the exact PR head SHA/i);
  assert.match(workflow, /each open PR is reconciled in its own per-PR concurrency group/i);
  assert.match(workflow, /repository owner must configure an active[\s\S]*ruleset requiring the `codex-approval` status/i);
  assert.match(workflow, /standard Actions and webhook events do not include PR reaction\s+creation\/removal/i);
  assert.match(workflow, /deleted-feedback revocation marker[\s\S]*persists\s+across scheduled runs/i);
  assert.match(workflow, /polls reactions every five minutes/i);
  assert.match(workflow, /green status by itself is therefore never enough/i);
  assert.match(workflow, /initial policy installation therefore needs the owner's normal bootstrap merge/i);
});

test('the selector can persist deletion revocation before the reconcile matrix', () => {
  const action = read('.github/workflows/codex-approval-status.yml');
  const selectorJob = action.split('\n  reconcile:\n')[0];

  assert.match(selectorJob, /permissions:[\s\S]*statuses:\s*write/);
});
