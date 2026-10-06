const test = require('node:test');
const assert = require('node:assert/strict');

const {
  STATUS_CONTEXT,
  evaluateCodexApproval,
  decideAgentMerge,
  publishCommitStatus,
  reconcilePullRequest,
  selectPullRequestNumbers,
} = require('../ci/codex-approval-status');

const headSha = 'a'.repeat(40);
const otherSha = 'b'.repeat(40);
const bot = 'chatgpt-codex-connector[bot]';
const requestAuthor = 'SilentSaint';

function review(body, sha = headSha, login = bot, id = 1) {
  return {
    id,
    user: { login },
    body: `${body}\n\n**Reviewed commit:** \`${sha}\``,
    created_at: '2026-10-06T10:02:00Z',
    updated_at: '2026-10-06T10:02:00Z',
  };
}

function request(head = headSha, createdAt = '2026-10-06T10:00:00Z') {
  return {
    id: 2,
    user: { login: requestAuthor },
    body: `@codex review\n<!-- codex-review-request: head=${head}; cycle=1 -->`,
    created_at: createdAt,
  };
}

function pullRequestReview(body, commitId = headSha, submittedAt = '2026-10-06T10:02:00Z', state = 'COMMENTED') {
  return {
    user: { login: bot },
    body: body ? `${body}\n\n**Reviewed commit:** \`${commitId.slice(0, 12)}\`` : '',
    commit_id: commitId,
    submitted_at: submittedAt,
    state,
  };
}

function snapshot(overrides = {}) {
  return {
    headSha,
    commits: [{ sha: headSha }],
    issueComments: [review("Codex Review: Didn't find any major issues. Keep it up!")],
    reviewComments: [],
    reviews: [],
    pullRequestReactions: [],
    ...overrides,
  };
}

test('a complete positive Codex review for the exact current head qualifies', () => {
  assert.deepEqual(evaluateCodexApproval(snapshot()), {
    authorized: true,
    signal: 'review-comment',
    reason: 'The latest Codex review clearly approves the current head.',
    headSha,
  });

  const canonicalFooter = review(
    "Codex Review: Didn't find any major issues. Hooray!\n\n<details> <summary>ℹ️ About Codex in GitHub</summary>\nIf Codex has suggestions, it will comment; otherwise it will react with 👍.\n</details>",
  );
  assert.equal(evaluateCodexApproval(snapshot({ issueComments: [canonicalFooter] })).authorized, true);
});

test('a current-head pull-request review qualifies and a later negative review revokes older approval', () => {
  const positiveReview = pullRequestReview("Codex Review: Didn't find any major issues. Keep it up!");
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [],
    reviews: [positiveReview],
  })).authorized, true, 'the submitted review body is a supported approval source');

  const olderPositiveComment = review("Codex Review: Didn't find any major issues. Keep it up!");
  const laterReview = pullRequestReview(
    'Codex Review: Please fix the retry bug.',
    headSha,
    '2026-10-06T10:04:00Z',
  );
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [olderPositiveComment],
    reviews: [laterReview],
  })).authorized, false, 'a newer submitted review response supersedes an older positive comment');

  const changedReview = pullRequestReview(
    "Codex Review: Didn't find any major issues.",
    headSha,
    '2026-10-06T10:05:00Z',
    'CHANGES_REQUESTED',
  );
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [],
    reviews: [changedReview],
  })).authorized, false, 'a changes-requested state is never an approval');

  const emptyLaterReview = pullRequestReview('', headSha, '2026-10-06T10:06:00Z', 'APPROVED');
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [olderPositiveComment],
    reviews: [emptyLaterReview],
  })).authorized, false, 'a newer empty review submission must not inherit an older approval');
});

test('a unique abbreviated reviewed commit is accepted only when it resolves to the current head', () => {
  const comment = review("Codex Review: Didn't find any major issues. Keep it up!", headSha.slice(0, 12));
  assert.equal(evaluateCodexApproval(snapshot({ issueComments: [comment] })).authorized, true);

  const ambiguous = snapshot({
    commits: [{ sha: headSha }, { sha: `${headSha.slice(0, 12)}${'c'.repeat(28)}` }],
    issueComments: [comment],
  });
  assert.equal(evaluateCodexApproval(ambiguous).authorized, false);
});

test('praise alone, mixed/actionable feedback, wrong authors, and stale heads fail closed', () => {
  for (const body of [
    'Nice work!',
    'LGTM, but please fix the retry behavior.',
    'No major issues; one blocking bug remains.',
    'Codex Review: Looks good to me. Consider documenting the retry behavior.',
    'Codex Review: LGTM; one potential improvement is clearer error handling.',
    'Codex Review: No major issues; the edge case is not covered.',
    'Codex Review: Not approved; no major issues found.',
    'Codex Review: NOT LGTM.',
    "Codex Review: It doesn't look good to me.",
    'Codex Review: I cannot say this is approved.',
    'Codex Review: LGTM, provided the CI tests pass.',
    'Codex Review: Approved pending the auth audit.',
    'Codex Review: Looks good, assuming CI passes.',
    'Codex Review: If CI checks pass, LGTM.',
    'Codex Review: No major issues except the retry path can hang.',
    'Codex Review: Looks good if you add a timeout before merging.',
  ]) {
    assert.equal(evaluateCodexApproval(snapshot({ issueComments: [review(body)] })).authorized, false, body);
  }
  assert.equal(
    evaluateCodexApproval(snapshot({ issueComments: [review("Codex Review: LGTM", headSha, 'random-user')] })).authorized,
    false,
  );
  assert.equal(
    evaluateCodexApproval(snapshot({ issueComments: [review("Codex Review: LGTM", otherSha)] })).authorized,
    false,
  );
});

test('an explicit no-actionable-findings review is a positive approval', () => {
  assert.equal(
    evaluateCodexApproval(snapshot({ issueComments: [review('Codex Review: No actionable findings.')] })).authorized,
    true,
  );
});

test('a newer negative Codex response invalidates an older positive review', () => {
  const positive = review('Codex Review: LGTM', headSha, bot, 1);
  const negative = {
    ...review('Codex Review: Please fix the boundary case.', headSha, bot, 3),
    created_at: '2026-10-06T10:04:00Z',
    updated_at: '2026-10-06T10:04:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({ issueComments: [positive, negative] })).authorized, false);

  const unstructuredNegative = {
    id: 4,
    user: { login: bot },
    body: 'The race in the retry path is still present.',
    created_at: '2026-10-06T10:05:00Z',
    updated_at: '2026-10-06T10:05:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [positive, unstructuredNegative],
  })).authorized, false, 'a later bot response cannot be ignored because its format is unexpected');
});

test('a same-second later Codex message fails closed using its higher GitHub id', () => {
  const approved = review('Codex Review: LGTM', headSha, bot, 10);
  const followUp = {
    id: 11,
    user: { login: bot },
    body: 'One more issue needs attention.',
    created_at: approved.created_at,
    updated_at: approved.updated_at,
  };
  assert.equal(evaluateCodexApproval(snapshot({ issueComments: [approved, followUp] })).authorized, false);
});

test('a PR-level Codex thumbs-up qualifies only after one recorded request for the unchanged head', () => {
  const reactions = [{
    id: 4,
    user: { login: bot },
    content: '+1',
    created_at: '2026-10-06T10:03:00Z',
  }];
  const requestComment = request();
  const base = snapshot({ issueComments: [requestComment], pullRequestReactions: reactions });
  assert.deepEqual(evaluateCodexApproval(base), {
    authorized: true,
    signal: 'pr-reaction',
    reason: 'The Codex thumbs-up follows exactly one recorded request for the current head.',
    headSha,
  });

  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [requestComment, request()],
    pullRequestReactions: reactions,
  })).authorized, false, 'multiple matching requests are ambiguous');

  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [request(otherSha)],
    pullRequestReactions: reactions,
  })).authorized, false, 'a request for another head is stale');

  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [request()],
    pullRequestReactions: [{ ...reactions[0], created_at: '2026-10-06T09:59:00Z' }],
  })).authorized, false, 'the reaction must follow the request');

  const editedAfterReaction = {
    ...request(),
    updated_at: '2026-10-06T10:04:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [editedAfterReaction],
    pullRequestReactions: reactions,
  })).authorized, false, 'an edited request marker must be timestamped at its latest edit');

  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [{ ...request(), body: '<!-- codex-review-request: head=' + headSha + '; cycle=1 -->' }],
    pullRequestReactions: reactions,
  })).authorized, false, 'the marker must be part of an actual Codex review request');

  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [{ ...request(), body: request().body.replace('cycle=1', 'cycle=11') }],
    pullRequestReactions: reactions,
  })).authorized, false, 'review requests cannot exceed the documented ten-cycle cap');
});

test('only a PR-level thumbs-up from the configured Codex bot can authorize', () => {
  const issueRequest = request();
  const thumbsUp = {
    id: 4,
    user: { login: bot },
    content: '+1',
    created_at: '2026-10-06T10:03:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [issueRequest],
    pullRequestReactions: [{ ...thumbsUp, user: { login: requestAuthor } }],
  })).authorized, false);
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [issueRequest],
    reviewComments: [thumbsUp],
    pullRequestReactions: [],
  })).authorized, false, 'review-comment reactions are not PR-level reactions');
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [issueRequest],
    pullRequestReactions: [{ ...thumbsUp, content: 'heart' }],
  })).authorized, false);
});

test('a later actionable inline Codex comment blocks the review-comment signal', () => {
  const inline = {
    id: 5,
    user: { login: bot },
    body: 'Please fix this null case.',
    created_at: '2026-10-06T10:03:00Z',
    updated_at: '2026-10-06T10:03:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({ reviewComments: [inline] })).authorized, false);
});

test('the merge decision requires current authorization and every independent gate', () => {
  const gates = {
    exactHead: true,
    mergeable: true,
    conversationsResolved: true,
    dockerGatePassed: true,
    requiredChecksPassed: true,
    branchCurrent: true,
    serverEnforcementVerified: true,
    serializationVerified: true,
    maintainerApprovalSatisfied: true,
  };
  assert.deepEqual(decideAgentMerge({ approval: { authorized: true, headSha }, gates, expectedHeadSha: headSha }), {
    allowed: true,
    failedGates: [],
  });

  for (const gate of Object.keys(gates)) {
    const denied = decideAgentMerge({
      approval: { authorized: true, headSha },
      gates: { ...gates, [gate]: false },
      expectedHeadSha: headSha,
    });
    assert.equal(denied.allowed, false, `${gate} must block merge`);
    assert.deepEqual(denied.failedGates, [gate]);
  }
  assert.equal(decideAgentMerge({ approval: { authorized: false, headSha }, gates, expectedHeadSha: headSha }).allowed, false);
  assert.equal(decideAgentMerge({ approval: { authorized: true, headSha }, gates: {}, expectedHeadSha: headSha }).allowed, false);
  assert.equal(decideAgentMerge({
    approval: { authorized: true, headSha },
    gates,
    expectedHeadSha: otherSha,
  }).allowed, false, 'the approval itself must be bound to the expected merge head');
});

test('the required status is published to the verified PR head, not the workflow SHA', async () => {
  let requestUrl;
  let requestOptions;
  const responseBody = { state: 'success', context: STATUS_CONTEXT };
  const status = await publishCommitStatus({
    apiBaseUrl: 'https://api.github.com/',
    owner: 'SilentSaint',
    repo: 'pesonal-accouts-app',
    sha: headSha,
    state: 'success',
    description: 'Current-head approval verified.',
    token: 'test-token',
    fetchImpl: async (url, options) => {
      requestUrl = url;
      requestOptions = options;
      return { ok: true, json: async () => responseBody };
    },
  });

  assert.equal(requestUrl, `https://api.github.com/repos/SilentSaint/pesonal-accouts-app/statuses/${headSha}`);
  assert.equal(requestOptions.method, 'POST');
  assert.equal(requestOptions.headers.Authorization, 'Bearer test-token');
  assert.deepEqual(JSON.parse(requestOptions.body), {
    state: 'success',
    context: 'codex-approval',
    description: 'Current-head approval verified.',
  });
  assert.equal(status, responseBody);
});

test('the status publisher rejects short SHAs and surfaces a denied status write', async () => {
  await assert.rejects(() => publishCommitStatus({
    owner: 'SilentSaint',
    repo: 'pesonal-accouts-app',
    sha: headSha.slice(0, 12),
    state: 'success',
    token: 'test-token',
  }), /full commit SHA/);

  await assert.rejects(() => publishCommitStatus({
    owner: 'SilentSaint',
    repo: 'pesonal-accouts-app',
    sha: headSha,
    state: 'success',
    token: 'test-token',
    fetchImpl: async () => ({ ok: false, status: 403 }),
  }), /rejected the codex-approval status update \(403\)/);
});

test('reconciliation writes pending then the evaluated status to the live PR head', async () => {
  const calls = [];
  const requestComment = request();
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, options });
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main' }, head: { sha: headSha } });
    }
    if (url.includes('/statuses/')) return responseFor({ ok: true });
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) return responseFor([
      review("Codex Review: Didn't find any major issues. Keep it up!"),
      requestComment,
    ]);
    if (url.endsWith('/pulls/177/reviews?per_page=100')) return responseFor([]);
    if (url.endsWith('/pulls/177/comments?per_page=100')) return responseFor([]);
    if (url.endsWith('/issues/177/reactions?per_page=100')) return responseFor([]);
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    targetUrl: 'https://github.com/SilentSaint/pesonal-accouts-app/actions/runs/9',
    botLogin: bot,
  });

  const statuses = calls.filter((call) => call.url.includes('/statuses/'));
  assert.equal(statuses.length, 2);
  assert.ok(statuses.every((call) => call.url.endsWith(`/statuses/${headSha}`)));
  assert.deepEqual(statuses.map((call) => JSON.parse(call.options.body).state), ['pending', 'success']);
  assert.ok(calls.some((call) => call.url.endsWith('/pulls/177/reviews?per_page=100')));
  assert.ok(calls.findIndex((call) => call.url.includes('/statuses/'))
    < calls.findIndex((call) => call.url.endsWith('/pulls/177/commits?per_page=100')));
});

test('a failed GitHub snapshot replaces prior success with an error status', async () => {
  const states = [];
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return { ok: true, json: async () => ({ state: 'open', base: { ref: 'main' }, head: { sha: headSha } }) };
    }
    if (url.includes('/statuses/')) {
      states.push(JSON.parse(options.body).state);
      return { ok: true, json: async () => ({}) };
    }
    return { ok: false, status: 503 };
  };

  await assert.rejects(() => reconcilePullRequest(
    177,
    { owner: 'SilentSaint', repo: 'pesonal-accouts-app' },
    { apiBaseUrl: 'https://api.github.com', token: 'test-token', fetchImpl, botLogin: bot },
  ), /GitHub API read failed \(503\)/);
  assert.deepEqual(states, ['pending', 'error']);
});

test('the five-minute reconciler does not rewrite an unchanged status on every poll', async () => {
  const postStates = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main' }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) {
      return responseFor([{
        context: 'codex-approval',
        state: 'success',
        created_at: '2026-10-06T10:05:00Z',
        creator: { login: 'github-actions[bot]' },
      }]);
    }
    if (url.includes('/statuses/')) {
      postStates.push(JSON.parse(options.body).state);
      return responseFor({});
    }
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) {
      return responseFor([review("Codex Review: Didn't find any major issues. Keep it up!")]);
    }
    if (url.endsWith('/pulls/177/reviews?per_page=100')) return responseFor([]);
    if (url.endsWith('/pulls/177/comments?per_page=100')) return responseFor([]);
    if (url.endsWith('/issues/177/reactions?per_page=100')) return responseFor([]);
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    eventName: 'schedule',
    botLogin: bot,
  });
  assert.deepEqual(postStates, []);
});

test('a same-context success from another app is not treated as the trusted status', async () => {
  const postStates = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main' }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) {
      return responseFor([{
        context: 'codex-approval',
        state: 'success',
        created_at: '2026-10-06T10:05:00Z',
        creator: { login: 'untrusted-workflow[bot]' },
      }]);
    }
    if (url.includes('/statuses/')) {
      postStates.push(JSON.parse(options.body).state);
      return responseFor({});
    }
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) {
      return responseFor([review("Codex Review: Didn't find any major issues. Keep it up!")]);
    }
    if (url.endsWith('/pulls/177/reviews?per_page=100')) return responseFor([]);
    if (url.endsWith('/pulls/177/comments?per_page=100')) return responseFor([]);
    if (url.endsWith('/issues/177/reactions?per_page=100')) return responseFor([]);
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    eventName: 'schedule',
    botLogin: bot,
  });
  assert.deepEqual(postStates, ['success']);
});

test('review events target one PR while scheduled discovery selects every open main PR', async () => {
  const repository = { owner: 'SilentSaint', repo: 'pesonal-accouts-app' };
  const calls = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const targeted = await selectPullRequestNumbers({
    eventName: 'pull_request_review',
    payload: { pull_request: { number: 177 } },
    repository,
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl: async () => { throw new Error('targeted events must not enumerate other PRs'); },
  });
  assert.deepEqual(targeted, [177]);

  const scheduled = await selectPullRequestNumbers({
    eventName: 'schedule',
    payload: {},
    repository,
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl: async (url) => {
      calls.push(url);
      return responseFor([{ number: 177 }, { number: 179 }]);
    },
  });
  assert.deepEqual(scheduled, [177, 179]);
  assert.deepEqual(calls, [
    'https://api.github.com/repos/SilentSaint/pesonal-accouts-app/pulls?state=open&base=main&per_page=100',
  ]);

  const issueComment = await selectPullRequestNumbers({
    eventName: 'issue_comment',
    payload: { issue: { number: 177 } },
    repository,
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl: async () => { throw new Error('issue comments must not enumerate PRs'); },
  });
  assert.deepEqual(issueComment, []);
});
