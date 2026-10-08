const test = require('node:test');
const assert = require('node:assert/strict');

const {
  STATUS_CONTEXT,
  evaluateCodexApproval,
  decideAgentMerge,
  publishCommitStatus,
  reconcilePullRequest,
  selectPullRequestTargets,
} = require('../ci/codex-approval-status');

const headSha = 'a'.repeat(40);
const otherSha = 'b'.repeat(40);
const previousBaseSha = 'c'.repeat(40);
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

function request(head = headSha, createdAt = '2026-10-06T10:00:00Z', base = otherSha) {
  return { ...requestForBase(base, head, createdAt), id: 2 };
}

function requestForBase(base, head = headSha, createdAt = '2026-10-06T10:00:00Z', cycle = 1) {
  return {
    id: 3,
    user: { login: requestAuthor },
    body: `@codex review\n<!-- codex-review-request: head=${head}; base=${base}; cycle=${cycle} -->`,
    created_at: createdAt,
    updated_at: createdAt,
  };
}

function pullRequestReview(body, commitId = headSha, submittedAt = '2026-10-06T10:02:00Z', state = 'COMMENTED') {
  return {
    user: { login: bot },
    body: body ? `${body}\n\n**Reviewed commit:** \`${commitId.slice(0, 12)}\`` : '',
    commit_id: commitId,
    review_created_at: submittedAt,
    submitted_at: submittedAt,
    state,
  };
}

function snapshot(overrides = {}) {
  return {
    headSha,
    baseSha: otherSha,
    commits: [{ sha: headSha }],
    issueComments: [review("Codex Review: Didn't find any major issues. Keep it up!")],
    reviewComments: [],
    reviews: [],
    pullRequestReactions: [],
    priorApprovalExists: true,
    priorApprovalBaseSha: otherSha,
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

  for (const body of [
    'Codex Review: I approve this PR.',
    'Codex Review: This is approved.',
    'Codex Review: This pull request is approved.',
    'Codex Review: No major issues found.',
  ]) {
    assert.equal(
      evaluateCodexApproval(snapshot({ issueComments: [review(body)] })).authorized,
      true,
      body,
    );
  }
});

test('approval evaluation fails closed when the current PR base SHA is unavailable', () => {
  assert.equal(evaluateCodexApproval(snapshot({ baseSha: undefined })).authorized, false,
    'a head-only approval cannot prove which base was reviewed');
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

test('a current-head approval requires a fresh Codex signal after the PR base changes', () => {
  const baseChange = {
    baseSha: otherSha,
    priorApprovalBaseSha: previousBaseSha,
    baseChangeInvalidation: {
      baseSha: otherSha,
      createdAt: '2026-10-06T10:03:00Z',
    },
  };
  const approvalBeforeBaseChange = review("Codex Review: Didn't find any major issues.");

  assert.equal(evaluateCodexApproval(snapshot({
    ...baseChange,
    issueComments: [approvalBeforeBaseChange],
  })).authorized, false, 'a head approval from the previous base cannot authorize a new diff');

  const approvalAfterBaseChange = {
    ...approvalBeforeBaseChange,
    created_at: '2026-10-06T10:04:00Z',
    updated_at: '2026-10-06T10:04:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({
    ...baseChange,
    issueComments: [requestForBase(otherSha, headSha, '2026-10-06T10:03:30Z'), approvalAfterBaseChange],
  })).authorized, true, 'a fresh exact-head review after base invalidation can authorize');

  assert.equal(evaluateCodexApproval(snapshot({
    ...baseChange,
    issueComments: [request()],
    pullRequestReactions: [{
      id: 4,
      user: { login: bot },
      content: '+1',
      created_at: '2026-10-06T10:05:00Z',
    }],
  })).authorized, false, 'a thumbs-up from before base invalidation cannot authorize');

  assert.equal(evaluateCodexApproval(snapshot({
    ...baseChange,
    issueComments: [requestForBase(otherSha, headSha, '2026-10-06T10:04:00Z')],
    pullRequestReactions: [{
      id: 4,
      user: { login: bot },
      content: '+1',
      created_at: '2026-10-06T10:05:00Z',
    }],
  })).authorized, true, 'a new request and thumbs-up after base invalidation can authorize');
});

test('a review approval requires request evidence bound to the live base without status history', () => {
  const approval = review("Codex Review: Didn't find any major issues.");
  const priorRequest = requestForBase(previousBaseSha);
  const currentBaseRequest = requestForBase(otherSha);

  assert.equal(evaluateCodexApproval(snapshot({
    baseSha: otherSha,
    priorApprovalExists: false,
    priorApprovalBaseSha: null,
    issueComments: [priorRequest, approval],
  })).authorized, false, 'an approval cannot borrow a previous-base request before the first status exists');

  assert.equal(evaluateCodexApproval(snapshot({
    baseSha: otherSha,
    priorApprovalExists: false,
    priorApprovalBaseSha: null,
    issueComments: [currentBaseRequest, approval],
  })).authorized, true, 'a current-head approval follows a request explicitly bound to the live base');
});

test('duplicate current-base review requests never authorize an approval', () => {
  const duplicateRequests = [
    requestForBase(otherSha, headSha, '2026-10-06T10:00:00Z', 1),
    requestForBase(otherSha, headSha, '2026-10-06T10:01:00Z', 2),
  ];
  const approval = review("Codex Review: Didn't find any major issues.");

  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [...duplicateRequests, approval],
  })).authorized, false,
  'multiple markers for the same head/base are ambiguous even when status history previously established the base');
});

test('a post-base-change review requires a new current-base request, not a later edit to an old approval', () => {
  const baseChange = {
    baseSha: otherSha,
    priorApprovalExists: true,
    priorApprovalBaseSha: previousBaseSha,
    baseChangeInvalidation: {
      baseSha: otherSha,
      createdAt: '2026-10-06T10:03:00Z',
    },
  };
  const oldRequest = requestForBase(previousBaseSha, headSha, '2026-10-06T10:00:00Z');
  const editedOldApproval = {
    ...review("Codex Review: Didn't find any major issues."),
    created_at: '2026-10-06T10:02:00Z',
    updated_at: '2026-10-06T10:04:00Z',
  };

  assert.equal(evaluateCodexApproval(snapshot({
    ...baseChange,
    issueComments: [
      oldRequest,
      requestForBase(otherSha, headSha, '2026-10-06T10:03:30Z'),
      editedOldApproval,
    ],
  })).authorized, false, 'editing or delivering an old approval after invalidation does not bind it to the new base');

  const newRequest = requestForBase(otherSha, headSha, '2026-10-06T10:04:00Z', 2);
  const freshApproval = {
    ...review("Codex Review: Didn't find any major issues.", headSha, bot, 4),
    created_at: '2026-10-06T10:05:00Z',
    updated_at: '2026-10-06T10:05:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({
    ...baseChange,
    issueComments: [oldRequest, newRequest, editedOldApproval, freshApproval],
  })).authorized, true, 'a response after a new request associated with the live base can authorize');
});

test('a review created before base invalidation cannot authorize when submitted afterward', () => {
  const currentBaseSha = 'd'.repeat(40);
  const pendingOldBaseReview = {
    ...pullRequestReview(
      "Codex Review: Didn't find any major issues.",
      headSha,
      '2026-10-06T10:04:00Z',
    ),
    review_created_at: '2026-10-06T10:02:00Z',
  };

  assert.equal(evaluateCodexApproval(snapshot({
    baseSha: currentBaseSha,
    priorApprovalExists: true,
    priorApprovalBaseSha: previousBaseSha,
    baseChangeInvalidation: {
      baseSha: currentBaseSha,
      createdAt: '2026-10-06T10:02:30Z',
    },
    issueComments: [requestForBase(currentBaseSha, headSha, '2026-10-06T10:03:00Z', 2)],
    reviews: [pendingOldBaseReview],
  })).authorized, false,
  'submission time cannot make a review that began before invalidation count as fresh');
});

test('a request marker inserted by editing an older comment cannot authorize a prior review', () => {
  const editedRequest = {
    ...request(),
    updated_at: '2026-10-06T10:03:00Z',
  };
  const alreadyCompletedReview = {
    ...review("Codex Review: Didn't find any major issues."),
    created_at: '2026-10-06T10:02:00Z',
    updated_at: '2026-10-06T10:02:00Z',
  };

  assert.equal(evaluateCodexApproval(snapshot({
    priorApprovalExists: false,
    priorApprovalBaseSha: null,
    issueComments: [editedRequest, alreadyCompletedReview],
  })).authorized, false,
  'the comment’s original creation time is not evidence that its edited-in marker triggered the review');
});

test('a same-second review cannot qualify when request timestamp precision is coarser', () => {
  const sameSecondRequest = {
    ...request(),
    created_at: '2026-10-06T10:02:00Z',
    updated_at: '2026-10-06T10:02:00Z',
  };
  const reviewStartedLaterWithinThatSecond = {
    ...pullRequestReview(
      "Codex Review: Didn't find any major issues.",
      headSha,
      '2026-10-06T10:02:00.500Z',
    ),
    review_created_at: '2026-10-06T10:02:00.250Z',
  };

  assert.equal(evaluateCodexApproval(snapshot({
    priorApprovalExists: false,
    priorApprovalBaseSha: null,
    issueComments: [sameSecondRequest],
    reviews: [reviewStartedLaterWithinThatSecond],
  })).authorized, false,
  'a finer-grained review timestamp cannot prove its start followed a coarser request timestamp');
});

test('an unsubmitted pending Codex review cannot authorize the current head', () => {
  const pendingReview = {
    ...pullRequestReview('Codex Review: LGTM'),
    state: 'PENDING',
    submitted_at: null,
    updated_at: null,
  };

  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [],
    reviews: [pendingReview],
  })).authorized, false);
});

test('a later review tied to an older head supersedes an earlier current-head approval', () => {
  const currentHeadApproval = pullRequestReview(
    "Codex Review: Didn't find any major issues. Keep it up!",
    headSha,
    '2026-10-06T10:04:00Z',
  );
  const staleHeadRejection = pullRequestReview(
    'Codex Review: The older change still has an unsafe retry case.',
    otherSha,
    '2026-10-06T10:05:00Z',
    'CHANGES_REQUESTED',
  );

  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [],
    reviews: [currentHeadApproval, staleHeadRejection],
  })).authorized, false);
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
    'Codex Review: No major issues. Rename foo to bar.',
    'Codex Review: LGTM would be premature.',
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
    'Codex Review: No major issues found, but the retry path can hang.',
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

test('interrogative approval verdicts fail closed', () => {
  for (const body of [
    'Codex Review: LGTM?',
    'Approved?',
    'No major issues?',
  ]) {
    assert.equal(
      evaluateCodexApproval(snapshot({ issueComments: [review(body)] })).authorized,
      false,
      body,
    );
  }
});

test('actionable text after the standard Codex footer still revokes approval', () => {
  const body = "Codex Review: Didn't find any major issues. Keep it up!\n\n"
    + '<details> <summary>ℹ️ About Codex in GitHub</summary>\n'
    + 'If Codex has suggestions, it will comment; otherwise it will react with 👍.\n'
    + '</details>\n\nCodex Review: Please fix the retry bug.';

  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [review(body)],
  })).authorized, false, 'the footer must not hide later actionable feedback');
});

test('an explicit no-actionable-findings review is a positive approval', () => {
  assert.equal(
    evaluateCodexApproval(snapshot({ issueComments: [review('Codex Review: No actionable findings.')] })).authorized,
    true,
  );
});

test('complete equivalent no-major-issues verdicts are positive approvals', () => {
  for (const body of [
    'Codex Review: No major issues identified.',
    'Codex Review: I found no major issues.',
  ]) {
    assert.equal(
      evaluateCodexApproval(snapshot({ issueComments: [review(body)] })).authorized,
      true,
      body,
    );
  }
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

  const editedOlderApproval = { ...positive, updated_at: '2026-10-06T10:06:00Z' };
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [editedOlderApproval, negative],
  })).authorized, false, 'editing an older approval cannot mask a later actionable review');

  const editedOlderSubmittedApproval = {
    ...pullRequestReview("Codex Review: Didn't find any major issues.", headSha, '2026-10-06T10:02:00Z'),
    updated_at: '2026-10-06T10:06:00Z',
  };
  const newerActionableSubmission = pullRequestReview(
    'Codex Review: Please fix the boundary case.',
    headSha,
    '2026-10-06T10:04:00Z',
  );
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [],
    reviews: [editedOlderSubmittedApproval, newerActionableSubmission],
  })).authorized, false, 'editing an older submitted approval cannot mask a later actionable review');
});

test('editing an older approval cannot hide newer unstructured or inline feedback', () => {
  const editedApproval = {
    ...review('Codex Review: LGTM', headSha, bot, 20),
    created_at: '2026-10-06T10:02:00Z',
    updated_at: '2026-10-06T10:06:00Z',
  };
  const newerUnstructuredFeedback = {
    id: 21,
    user: { login: bot },
    body: 'The retry path still needs a fix.',
    created_at: '2026-10-06T10:04:00Z',
    updated_at: '2026-10-06T10:04:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [editedApproval, newerUnstructuredFeedback],
  })).authorized, false, 'an edit cannot hide a newer top-level finding');

  const newerInlineFeedback = { ...newerUnstructuredFeedback, id: 22 };
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [editedApproval],
    reviewComments: [newerInlineFeedback],
  })).authorized, false, 'an edit cannot hide a newer inline finding');

  const editedSubmittedApproval = {
    ...pullRequestReview('Codex Review: LGTM', headSha, '2026-10-06T10:02:00Z'),
    id: 23,
    updated_at: '2026-10-06T10:06:00Z',
  };
  const newerSubmittedApproval = {
    ...pullRequestReview("Codex Review: Didn't find any major issues.", headSha, '2026-10-06T10:04:00Z'),
    id: 24,
    updated_at: '2026-10-06T10:04:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [],
    reviews: [editedSubmittedApproval, newerSubmittedApproval],
  })).authorized, false, 'an edit to an older submitted review cannot hide later approval activity');
});

test('a later issue comment revokes a review even when GitHub resource IDs collide', () => {
  const currentHeadApproval = {
    ...pullRequestReview('Codex Review: LGTM', headSha, '2026-10-06T10:02:00Z'),
    id: 7,
  };
  const laterIssueComment = {
    id: 7,
    user: { login: bot },
    body: 'The retry path still needs attention.',
    created_at: '2026-10-06T10:04:00Z',
    updated_at: '2026-10-06T10:04:00Z',
  };

  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [laterIssueComment],
    reviews: [currentHeadApproval],
  })).authorized, false, 'IDs from issue comments and submitted reviews are not interchangeable');
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

test('same-second feedback from different GitHub resources fails closed', () => {
  const approval = review('Codex Review: LGTM', headSha, bot, 10);
  const inlineRejection = {
    id: 9,
    user: { login: bot },
    body: 'The retry path still needs a fix.',
    created_at: approval.created_at,
    updated_at: approval.updated_at,
  };
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [approval],
    reviewComments: [inlineRejection],
  })).authorized, false, 'IDs from comments and inline reviews do not order a timestamp tie');

  const submittedRejection = {
    ...pullRequestReview('Codex Review: Please fix the retry path.'),
    id: 9,
  };
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [approval],
    reviews: [submittedRejection],
  })).authorized, false, 'IDs from issue comments and submitted reviews do not order a timestamp tie');

  const editedApproval = { ...approval, updated_at: '2026-10-06T10:06:00Z' };
  const sameTimeChangesRequested = {
    ...pullRequestReview('Codex Review: Please fix the retry path.', headSha, approval.created_at, 'CHANGES_REQUESTED'),
    updated_at: '2026-10-06T10:02:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [editedApproval],
    reviews: [sameTimeChangesRequested],
  })).authorized, false, 'an edit cannot break a tie between cross-resource review responses');
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
    baseSha: otherSha,
    issueComments: [
      requestForBase(otherSha, headSha, '2026-10-06T10:00:00Z', 1),
      requestForBase(otherSha, headSha, '2026-10-06T10:02:00Z', 2),
    ],
    pullRequestReactions: [{ ...reactions[0], created_at: '2026-10-06T10:03:00Z' }],
  })).authorized, false, 'multiple requests for the same head and base remain ambiguous');

  const earlierReview = {
    ...review("Codex Review: Didn't find any major issues."),
    created_at: '2026-10-06T09:58:00Z',
    updated_at: '2026-10-06T09:58:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({
    baseSha: otherSha,
    priorApprovalExists: true,
    priorApprovalBaseSha: otherSha,
    issueComments: [earlierReview, requestForBase(otherSha, headSha, '2026-10-06T10:00:00Z')],
    pullRequestReactions: [{ ...reactions[0], created_at: '2026-10-06T10:03:00Z' }],
  })).authorized, true,
  'a new thumbs-up can authorize after the unique request even when an earlier review response remains visible');

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
    created_at: '2026-10-06T10:04:00Z',
    updated_at: '2026-10-06T10:05:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({
    issueComments: [editedAfterReaction],
    pullRequestReactions: reactions,
  })).authorized, false, 'editing a marker cannot make an earlier reaction follow the request');

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

test('a later or timestamp-ambiguous Codex reaction revokes the PR-level thumbs-up', () => {
  for (const negativeAt of ['2026-10-06T10:04:00Z', '2026-10-06T10:03:00Z']) {
    const reactions = [
      { id: 4, user: { login: bot }, content: '+1', created_at: '2026-10-06T10:03:00Z' },
      { id: 5, user: { login: bot }, content: '-1', created_at: negativeAt },
    ];

    assert.equal(evaluateCodexApproval(snapshot({
      issueComments: [request()],
      pullRequestReactions: reactions,
    })).authorized, false, 'a newer or equally-timed thumbs-down is ambiguous');
  }
});

test('a later or timestamp-ambiguous Codex thumbs-down revokes comment and submitted-review approvals', () => {
  const approvals = [
    { issueComments: [review("Codex Review: Didn't find any major issues.")] },
    { issueComments: [], reviews: [pullRequestReview("Codex Review: Didn't find any major issues.")] },
  ];

  for (const approval of approvals) {
    for (const negativeAt of ['2026-10-06T10:04:00Z', '2026-10-06T10:02:00Z']) {
      const thumbsDown = {
        id: 5,
        user: { login: bot },
        content: '-1',
        created_at: negativeAt,
      };
      assert.equal(evaluateCodexApproval(snapshot({
        ...approval,
        pullRequestReactions: [thumbsDown],
      })).authorized, false, 'a later or equally timed PR-level thumbs-down supersedes either review signal');
    }

    assert.equal(evaluateCodexApproval(snapshot({
      ...approval,
      pullRequestReactions: [{
        id: 5,
        user: { login: bot },
        content: '-1',
        created_at: '2026-10-06T10:01:00Z',
      }],
    })).authorized, true, 'an earlier thumbs-down does not supersede a later approval');
  }

  const editedApprovals = [
    { issueComments: [{
      ...review("Codex Review: Didn't find any major issues."),
      created_at: '2026-10-06T10:02:00Z',
      updated_at: '2026-10-06T10:04:00Z',
    }] },
    { issueComments: [], reviews: [{
      ...pullRequestReview("Codex Review: Didn't find any major issues.", headSha, '2026-10-06T10:02:00Z'),
      updated_at: '2026-10-06T10:04:00Z',
    }] },
  ];
  for (const approval of editedApprovals) {
    assert.equal(evaluateCodexApproval(snapshot({
      ...approval,
      pullRequestReactions: [{
        id: 6,
        user: { login: bot },
        content: '-1',
        created_at: '2026-10-06T10:03:00Z',
      }],
    })).authorized, false, 'editing an earlier approval cannot mask a later thumbs-down');
  }
});

test('a persisted thumbs-down revocation blocks removed feedback until a fresh base-bound review', () => {
  const oldRequest = requestForBase(otherSha, headSha, '2026-10-06T10:00:00Z');
  const oldApproval = {
    ...review("Codex Review: Didn't find any major issues."),
    created_at: '2026-10-06T10:02:00Z',
    updated_at: '2026-10-06T10:02:00Z',
  };

  assert.equal(evaluateCodexApproval(snapshot({
    baseSha: otherSha,
    issueComments: [oldRequest, oldApproval],
    pullRequestReactions: [],
  }), { negativeReactionRevokedAt: '2026-10-06T10:03:00Z' }).authorized, false,
  'removing a previously observed thumbs-down cannot restore the earlier approval');

  const freshApproval = {
    ...review("Codex Review: Didn't find any major issues.", headSha, bot, 4),
    created_at: '2026-10-06T10:05:00Z',
    updated_at: '2026-10-06T10:05:00Z',
  };
  assert.equal(evaluateCodexApproval(snapshot({
    baseSha: otherSha,
    issueComments: [oldRequest, oldApproval, freshApproval],
    pullRequestReactions: [],
  }), { negativeReactionRevokedAt: '2026-10-06T10:03:00Z' }).authorized, true,
  'a newly submitted approval after the revocation can restore authorization');

  assert.equal(evaluateCodexApproval(snapshot({
    baseSha: otherSha,
    issueComments: [oldRequest],
    pullRequestReactions: [{
      id: 6,
      user: { login: bot },
      content: '+1',
      created_at: '2026-10-06T10:05:00Z',
    }],
  }), { negativeReactionRevokedAt: '2026-10-06T10:03:00Z' }).authorized, true,
  'a newer thumbs-up can clear the persisted revocation after the single recorded request');
});

test('scheduled reconciliation persists a negative-reaction revocation until a fresh review', async () => {
  const statusHistory = [{
    context: STATUS_CONTEXT,
    state: 'success',
    created_at: '2026-10-06T10:03:00Z',
    description: `base-sha=${otherSha}; prior approval`,
    creator: { login: 'github-actions[bot]' },
  }];
  const oldRequest = requestForBase(otherSha, headSha, '2026-10-06T10:00:00Z');
  const oldApproval = {
    ...review("Codex Review: Didn't find any major issues."),
    created_at: '2026-10-06T10:02:00Z',
    updated_at: '2026-10-06T10:02:00Z',
  };
  let issueComments = [oldRequest, oldApproval];
  let pullRequestReactions = [{
    id: 5,
    user: { login: bot },
    content: '-1',
    created_at: '2026-10-06T10:04:00Z',
  }];
  const published = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) return responseFor([...statusHistory]);
    if (url.includes('/statuses/')) {
      const status = JSON.parse(options.body);
      published.push(status);
      statusHistory.unshift({
        context: STATUS_CONTEXT,
        state: status.state,
        created_at: status.state === 'pending' ? '2026-10-06T10:05:00Z' : '2026-10-06T10:05:01Z',
        description: status.description,
        creator: { login: 'github-actions[bot]' },
      });
      return responseFor({});
    }
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) return responseFor(issueComments);
    if (url.endsWith('/pulls/177/comments?per_page=100')) return responseFor([]);
    if (url.endsWith('/issues/177/reactions?per_page=100')) return responseFor(pullRequestReactions);
    if (url.endsWith('/graphql')) return responseFor({ data: { repository: { pullRequest: { reviews: {
      nodes: [], pageInfo: { hasNextPage: false, endCursor: null },
    } } } } });
    throw new Error(`Unexpected API URL: ${url}`);
  };
  const options = {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    botLogin: bot,
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    ...options,
    eventName: 'schedule',
  });
  assert.equal(published.at(-1).state, 'failure');
  assert.match(published.at(-1).description, /negative-reaction-review-required/);

  published.length = 0;
  pullRequestReactions = [];
  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    ...options,
    eventName: 'schedule',
  });
  assert.deepEqual(published, [], 'the scheduled poll cannot restore success after the reaction disappears');
  assert.match(statusHistory[0].description, /negative-reaction-review-required/);

  issueComments = [
    ...issueComments,
    {
      ...review('Codex Review: Please fix the retry boundary.', headSha, bot, 6),
      created_at: '2026-10-06T10:06:00Z',
      updated_at: '2026-10-06T10:06:00Z',
    },
  ];
  published.length = 0;
  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    ...options,
    eventName: 'pull_request_review',
  });
  assert.deepEqual(published.map(status => status.state), ['pending', 'failure']);
  assert.match(published.at(-1).description, /negative-reaction-review-required/);

  published.length = 0;
  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    ...options,
    eventName: 'schedule',
  });
  assert.deepEqual(published, [], 'polling does not rewrite an unchanged failure with an active revocation');

  issueComments = [
    ...issueComments,
    {
      ...review("Codex Review: Didn't find any major issues.", headSha, bot, 6),
      created_at: '2026-10-06T10:07:00Z',
      updated_at: '2026-10-06T10:07:00Z',
    },
  ];
  published.length = 0;
  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    ...options,
    eventName: 'pull_request_review',
  });
  assert.deepEqual(published.map(status => status.state), ['pending', 'success']);
  assert.match(published.at(-1).description, /base-sha=/);
});

test('a fresh current-base review clears a negative-reaction revocation from an earlier base', async () => {
  const statusHistory = [
    {
      context: STATUS_CONTEXT,
      state: 'failure',
      created_at: '2026-10-06T10:03:00Z',
      description: `base-sha=${previousBaseSha}; negative-reaction-review-required: prior review was revoked`,
      creator: { login: 'github-actions[bot]' },
    },
    {
      context: STATUS_CONTEXT,
      state: 'success',
      created_at: '2026-10-06T10:04:00Z',
      description: `base-sha=${otherSha}; prior current-base approval`,
      creator: { login: 'github-actions[bot]' },
    },
  ];
  const issueComments = [
    requestForBase(otherSha, headSha, '2026-10-06T10:05:00Z', 2),
    {
      ...review("Codex Review: Didn't find any major issues.", headSha, bot, 7),
      created_at: '2026-10-06T10:06:00Z',
      updated_at: '2026-10-06T10:06:00Z',
    },
  ];
  const published = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) return responseFor([...statusHistory]);
    if (url.includes('/statuses/')) {
      published.push(JSON.parse(options.body));
      return responseFor({});
    }
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) return responseFor(issueComments);
    if (url.endsWith('/pulls/177/comments?per_page=100')) return responseFor([]);
    if (url.endsWith('/issues/177/reactions?per_page=100')) return responseFor([]);
    if (url.endsWith('/graphql')) return responseFor({ data: { repository: { pullRequest: { reviews: {
      nodes: [], pageInfo: { hasNextPage: false, endCursor: null },
    } } } } });
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    botLogin: bot,
    eventName: 'pull_request_review',
  });

  assert.deepEqual(published.map(status => status.state), ['pending', 'success']);
  assert.match(published.at(-1).description, new RegExp(`base-sha=${otherSha};`));
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
    codexReconciliationSucceeded: true,
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
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) return responseFor([]);
    if (url.includes('/statuses/')) return responseFor({ ok: true });
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) return responseFor([
      review("Codex Review: Didn't find any major issues. Keep it up!"),
      requestForBase(otherSha, headSha, requestComment.created_at),
    ]);
    if (url.endsWith('/graphql')) return responseFor({ data: { repository: { pullRequest: { reviews: {
      nodes: [], pageInfo: { hasNextPage: false, endCursor: null },
    } } } } });
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

  const statuses = calls.filter((call) => call.options.method === 'POST' && call.url.includes('/statuses/'));
  assert.equal(statuses.length, 2);
  assert.ok(statuses.every((call) => call.url.endsWith(`/statuses/${headSha}`)));
  assert.deepEqual(statuses.map((call) => JSON.parse(call.options.body).state), ['pending', 'success']);
  assert.ok(statuses.every((call) => JSON.parse(call.options.body).description.includes(`base-sha=${otherSha}`)));
  assert.ok(calls.some((call) => call.url.endsWith('/graphql') && call.options.method === 'POST'));
  assert.ok(calls.findIndex((call) => call.options.method === 'POST' && call.url.includes('/statuses/'))
    < calls.findIndex((call) => call.url.endsWith('/pulls/177/commits?per_page=100')));
});

test('reconciliation invalidates a prior approval when the live PR base SHA changes', async () => {
  const calls = [];
  const priorStatus = {
    context: STATUS_CONTEXT,
    state: 'success',
    created_at: '2026-10-06T10:03:00Z',
    description: `base-sha=${previousBaseSha}; prior approval`,
    creator: { login: 'github-actions[bot]' },
  };
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, options });
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) return responseFor([priorStatus]);
    if (url.includes('/statuses/')) return responseFor({});
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) {
      return responseFor([review("Codex Review: Didn't find any major issues.")]);
    }
    if (url.endsWith('/pulls/177/comments?per_page=100')) return responseFor([]);
    if (url.endsWith('/issues/177/reactions?per_page=100')) return responseFor([]);
    if (url.endsWith('/graphql')) return responseFor({ data: { repository: { pullRequest: { reviews: {
      nodes: [], pageInfo: { hasNextPage: false, endCursor: null },
    } } } } });
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    eventName: 'schedule',
    botLogin: bot,
  });

  const statuses = calls.filter((call) => call.options.method === 'POST' && call.url.includes('/statuses/'))
    .map((call) => JSON.parse(call.options.body));
  assert.deepEqual(statuses.map((status) => status.state), ['failure']);
  assert.match(statuses[0].description, new RegExp(`base-sha=${otherSha}`));
  assert.match(statuses[0].description, /base-change-review-required/);
  assert.equal(calls.some((call) => call.url.endsWith('/pulls/177/commits?per_page=100')), false,
    'a stale-base approval must be revoked before selecting approval feedback');
});

test('a base retarget invalidates an old review even before the policy has recorded approval', async () => {
  const calls = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, options });
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) return responseFor([]);
    if (url.includes('/statuses/')) return responseFor({});
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    eventName: 'pull_request_target',
    eventPayload: { action: 'edited', changes: { base: { ref: { from: 'release' } } } },
    botLogin: bot,
  });

  const statuses = calls.filter((call) => call.options.method === 'POST' && call.url.includes('/statuses/'))
    .map((call) => JSON.parse(call.options.body));
  assert.deepEqual(statuses.map((status) => status.state), ['pending', 'failure']);
  assert.match(statuses[1].description, /base-change-review-required/);
  assert.match(statuses[1].description, new RegExp(`base-sha=${otherSha}`));
  assert.equal(calls.some((call) => call.url.endsWith('/issues/177/comments?per_page=100')), false,
    'the prior-base review must not be read as approval after a base retarget');
});

test('scheduled reconciliation detects base drift from a failure status without a prior success', async () => {
  const calls = [];
  const oldBaseFailure = {
    context: STATUS_CONTEXT,
    state: 'failure',
    created_at: '2026-10-06T10:02:00Z',
    description: `base-sha=${previousBaseSha}; Codex approval was not verified.`,
    creator: { login: 'github-actions[bot]' },
  };
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, options });
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) return responseFor([oldBaseFailure]);
    if (url.includes('/statuses/')) return responseFor({});
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    eventName: 'schedule',
    botLogin: bot,
  });

  const statuses = calls.filter((call) => call.options.method === 'POST' && call.url.includes('/statuses/'))
    .map((call) => JSON.parse(call.options.body));
  assert.equal(statuses.length, 1);
  assert.equal(statuses[0].state, 'failure');
  assert.match(statuses[0].description, /base-change-review-required/);
  assert.equal(calls.some((call) => call.url.endsWith('/pulls/177/commits?per_page=100')), false,
    'base drift is invalidated before preexisting approval feedback can be examined');
});

test('a fresh review after the persisted base invalidation restores the current-base status', async () => {
  const postStates = [];
  const priorStatuses = [
    {
      context: STATUS_CONTEXT,
      state: 'success',
      created_at: '2026-10-06T10:02:00Z',
      description: `base-sha=${previousBaseSha}; prior approval`,
      creator: { login: 'github-actions[bot]' },
    },
    {
      context: STATUS_CONTEXT,
      state: 'failure',
      created_at: '2026-10-06T10:03:00Z',
      description: `base-sha=${otherSha}; base-change-review-required: fresh review required`,
      creator: { login: 'github-actions[bot]' },
    },
  ];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) return responseFor(priorStatuses);
    if (url.includes('/statuses/')) {
      postStates.push(JSON.parse(options.body));
      return responseFor({});
    }
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) {
      return responseFor([
        requestForBase(otherSha, headSha, '2026-10-06T10:03:30Z'),
        {
        ...review("Codex Review: Didn't find any major issues."),
        created_at: '2026-10-06T10:04:00Z',
        updated_at: '2026-10-06T10:04:00Z',
        },
      ]);
    }
    if (url.endsWith('/pulls/177/comments?per_page=100')) return responseFor([]);
    if (url.endsWith('/issues/177/reactions?per_page=100')) return responseFor([]);
    if (url.endsWith('/graphql')) return responseFor({ data: { repository: { pullRequest: { reviews: {
      nodes: [], pageInfo: { hasNextPage: false, endCursor: null },
    } } } } });
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    eventName: 'pull_request_review',
    botLogin: bot,
  });

  assert.deepEqual(postStates.map((status) => status.state), ['pending', 'success']);
  assert.ok(postStates[1].description.includes(`base-sha=${otherSha}`));
});

test('reconciliation rejects a late submission whose review was created before base invalidation', async () => {
  const postStates = [];
  const priorStatuses = [
    {
      context: STATUS_CONTEXT,
      state: 'success',
      created_at: '2026-10-06T10:02:00Z',
      description: `base-sha=${previousBaseSha}; prior approval`,
      creator: { login: 'github-actions[bot]' },
    },
    {
      context: STATUS_CONTEXT,
      state: 'failure',
      created_at: '2026-10-06T10:03:00Z',
      description: `base-sha=${otherSha}; base-change-review-required: fresh review required`,
      creator: { login: 'github-actions[bot]' },
    },
  ];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) return responseFor(priorStatuses);
    if (url.includes('/statuses/')) {
      postStates.push(JSON.parse(options.body));
      return responseFor({});
    }
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) {
      return responseFor([requestForBase(otherSha, headSha, '2026-10-06T10:03:30Z', 2)]);
    }
    if (url.endsWith('/pulls/177/comments?per_page=100')) return responseFor([]);
    if (url.endsWith('/issues/177/reactions?per_page=100')) return responseFor([]);
    if (url.endsWith('/graphql')) {
      const query = JSON.parse(options.body).query;
      assert.match(query, /\bcreatedAt\b/, 'the review query must fetch immutable review creation time');
      return responseFor({ data: { repository: { pullRequest: { reviews: {
        nodes: [{
          fullDatabaseId: '53',
          author: { login: bot },
          body: "Codex Review: Didn't find any major issues.",
          state: 'COMMENTED',
          commit: { oid: headSha },
          createdAt: '2026-10-06T10:02:30Z',
          submittedAt: '2026-10-06T10:04:00Z',
          updatedAt: '2026-10-06T10:04:00Z',
          lastEditedAt: null,
        }],
        pageInfo: { hasNextPage: false, endCursor: null },
      } } } } });
    }
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    eventName: 'pull_request_review',
    botLogin: bot,
  });

  assert.deepEqual(postStates.map((status) => status.state), ['pending', 'failure']);
  assert.match(postStates[1].description, /An older Codex review was edited or delivered after the recorded request/);
});

test('an edit to an older current-head review supersedes a newer Codex approval', async () => {
  const statuses = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const editedReview = {
    fullDatabaseId: '51',
    author: { login: bot },
    body: 'Codex Review: Please fix the retry boundary.',
    state: 'COMMENTED',
    commit: { oid: headSha },
    createdAt: '2026-10-06T10:01:00Z',
    submittedAt: '2026-10-06T10:02:00Z',
    updatedAt: '2026-10-06T10:06:00Z',
    lastEditedAt: '2026-10-06T10:06:00Z',
  };
  const newerApproval = {
    fullDatabaseId: '52',
    author: { login: bot },
    body: "Codex Review: Didn't find any major issues. Keep it up!",
    state: 'COMMENTED',
    commit: { oid: headSha },
    createdAt: '2026-10-06T10:03:00Z',
    submittedAt: '2026-10-06T10:04:00Z',
    updatedAt: '2026-10-06T10:04:00Z',
    lastEditedAt: null,
  };
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) return responseFor([]);
    if (url.includes('/statuses/')) {
      statuses.push(JSON.parse(options.body).state);
      return responseFor({});
    }
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) return responseFor([]);
    if (url.endsWith('/pulls/177/comments?per_page=100')) return responseFor([]);
    if (url.endsWith('/issues/177/reactions?per_page=100')) return responseFor([]);
    if (url.endsWith('/graphql')) {
      return responseFor({ data: { repository: { pullRequest: { reviews: {
        nodes: [editedReview, newerApproval],
        pageInfo: { hasNextPage: false, endCursor: null },
      } } } } });
    }
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    eventName: 'pull_request_review',
    botLogin: bot,
  });

  assert.deepEqual(statuses, ['pending', 'failure']);
});

test('deleting Codex feedback cannot restore an older approval', async () => {
  const statuses = [];
  const statusHistory = [{
    context: 'codex-approval',
    state: 'success',
    created_at: '2026-10-06T10:03:00Z',
    description: `base-sha=${otherSha}; The prior Codex review was authorized.`,
    creator: { login: 'github-actions[bot]' },
  }];
  let currentReview = review('Codex Review: LGTM', headSha, bot, 10);
  let currentRequest = requestForBase(otherSha, headSha, '2026-10-06T10:00:00Z');
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) {
      return responseFor([...statusHistory]);
    }
    if (url.includes('/statuses/')) {
      const state = JSON.parse(options.body).state;
      statuses.push(state);
      statusHistory.unshift({
        context: 'codex-approval',
        state,
        created_at: state === 'pending' ? '2026-10-06T10:10:00Z' : '2026-10-06T10:10:01Z',
        description: JSON.parse(options.body).description,
        creator: { login: 'github-actions[bot]' },
      });
      return responseFor({});
    }
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) {
      return responseFor([currentRequest, currentReview]);
    }
    if (url.endsWith('/pulls/177/comments?per_page=100')) return responseFor([]);
    if (url.endsWith('/issues/177/reactions?per_page=100')) return responseFor([]);
    if (url.endsWith('/graphql')) return responseFor({ data: { repository: { pullRequest: { reviews: {
      nodes: [], pageInfo: { hasNextPage: false, endCursor: null },
    } } } } });
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    eventName: 'issue_comment',
    eventPayload: {
      action: 'deleted',
      issue: { number: 177, pull_request: { url: 'https://api.github.com/repos/SilentSaint/pesonal-accouts-app/pulls/177' } },
      comment: { id: 9, user: { login: bot }, body: 'Codex Review: Please fix the retry bug.' },
    },
    botLogin: bot,
  });

  assert.deepEqual(statuses, ['pending', 'failure']);
  assert.equal(evaluateCodexApproval(snapshot(), {
    botLogin: bot,
    eventName: 'pull_request_review_comment',
    eventPayload: {
      action: 'deleted',
      pull_request: { number: 177 },
      comment: { id: 8, user: { login: bot }, body: 'The retry path still needs a fix.' },
    },
  }).authorized, false, 'deleting an inline Codex comment also requires a fresh review');

  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    eventName: 'schedule',
    botLogin: bot,
  });

  assert.deepEqual(statuses, ['pending', 'failure'], 'the scheduled pass must preserve the revocation');

  currentReview = review('Codex Review: LGTM', headSha, bot, 11);
  currentReview.created_at = '2026-10-06T10:15:00Z';
  currentReview.updated_at = '2026-10-06T10:15:00Z';
  await reconcilePullRequest(177, { owner: 'SilentSaint', repo: 'pesonal-accouts-app' }, {
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl,
    eventName: 'schedule',
    botLogin: bot,
  });
  assert.deepEqual(statuses, ['pending', 'failure', 'success'], 'a fresh post-revocation approval restores authorization');
});

test('a failed GitHub snapshot replaces prior success with an error status', async () => {
  const states = [];
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return { ok: true, json: async () => ({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } }) };
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

test('a failed PR read overwrites a prior status when the trigger provides its head SHA', async () => {
  const states = [];
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) return { ok: false, status: 503 };
    if (url.includes('/statuses/')) {
      states.push(JSON.parse(options.body).state);
      return { ok: true, json: async () => ({}) };
    }
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await assert.rejects(() => reconcilePullRequest(
    177,
    { owner: 'SilentSaint', repo: 'pesonal-accouts-app' },
    {
      apiBaseUrl: 'https://api.github.com',
      token: 'test-token',
      fetchImpl,
      eventName: 'pull_request_target',
      headSha,
      botLogin: bot,
    },
  ), /GitHub API read failed \(503\)/);
  assert.deepEqual(states, ['pending', 'error']);
});

test('a failed pending-status write is followed by a fail-closed error status', async () => {
  const states = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) return responseFor([]);
    if (url.includes('/statuses/')) {
      const state = JSON.parse(options.body).state;
      states.push(state);
      return state === 'pending' ? { ok: false, status: 503 } : responseFor({});
    }
    throw new Error(`Unexpected API URL: ${url}`);
  };

  await assert.rejects(() => reconcilePullRequest(
    177,
    { owner: 'SilentSaint', repo: 'pesonal-accouts-app' },
    {
      apiBaseUrl: 'https://api.github.com',
      token: 'test-token',
      fetchImpl,
      eventName: 'pull_request_target',
      headSha,
      botLogin: bot,
    },
  ), /GitHub rejected the codex-approval status update \(503\)/);
  assert.deepEqual(states, ['pending', 'error']);
});

test('the five-minute reconciler does not rewrite an unchanged status on every poll', async () => {
  const postStates = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/pulls/177')) {
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
    }
    if (url.endsWith(`/commits/${headSha}/statuses?per_page=100`)) {
      return responseFor([{
        context: 'codex-approval',
        state: 'success',
        created_at: '2026-10-06T10:05:00Z',
        description: `base-sha=${otherSha}; prior approval`,
        creator: { login: 'github-actions[bot]' },
      }]);
    }
    if (url.includes('/statuses/')) {
      postStates.push(JSON.parse(options.body).state);
      return responseFor({});
    }
    if (url.endsWith('/pulls/177/commits?per_page=100')) return responseFor([{ sha: headSha }]);
    if (url.endsWith('/issues/177/comments?per_page=100')) {
      return responseFor([
        requestForBase(otherSha),
        review("Codex Review: Didn't find any major issues. Keep it up!"),
      ]);
    }
    if (url.endsWith('/graphql')) return responseFor({ data: { repository: { pullRequest: { reviews: {
      nodes: [], pageInfo: { hasNextPage: false, endCursor: null },
    } } } } });
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
      return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
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
      return responseFor([
        requestForBase(otherSha),
        review("Codex Review: Didn't find any major issues. Keep it up!"),
      ]);
    }
    if (url.endsWith('/graphql')) return responseFor({ data: { repository: { pullRequest: { reviews: {
      nodes: [], pageInfo: { hasNextPage: false, endCursor: null },
    } } } } });
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

test('target selection persists deleted bot feedback before reconciliation can be superseded', async () => {
  const calls = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const targets = await selectPullRequestTargets({
    eventName: 'issue_comment',
    payload: {
      action: 'deleted',
      issue: { number: 177, pull_request: { url: 'https://api.github.com/repos/SilentSaint/pesonal-accouts-app/pulls/177' } },
      comment: { id: 9, user: { login: bot }, body: 'The retry path still needs a fix.' },
    },
    repository: { owner: 'SilentSaint', repo: 'pesonal-accouts-app' },
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl: async (url, options = {}) => {
      calls.push({ url, options });
      if (url.endsWith('/pulls/177')) {
        return responseFor({ state: 'open', base: { ref: 'main', sha: otherSha }, head: { sha: headSha } });
      }
      if (url.endsWith(`/statuses/${headSha}`)) return responseFor({});
      throw new Error(`Unexpected API URL: ${url}`);
    },
  });

  assert.deepEqual(targets, [{ number: 177, head_sha: headSha }]);
  const revocation = calls.find((call) => call.options.method === 'POST');
  assert.ok(revocation, 'the deletion must be recorded before the matrix reconciliation is queued');
  assert.deepEqual(JSON.parse(revocation.options.body), {
    state: 'failure',
    context: 'codex-approval',
    description: 'Codex review feedback was deleted; a fresh review is required.',
  });
});

test('deleted feedback stays revoked when its PR is closed or retargeted before reopening', async () => {
  const calls = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const targets = await selectPullRequestTargets({
    eventName: 'issue_comment',
    payload: {
      action: 'deleted',
      issue: { number: 177, pull_request: { url: 'https://api.github.com/repos/SilentSaint/pesonal-accouts-app/pulls/177' } },
      comment: { id: 10, user: { login: bot }, body: 'The retry path still needs a fix.' },
    },
    repository: { owner: 'SilentSaint', repo: 'pesonal-accouts-app' },
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl: async (url, options = {}) => {
      calls.push({ url, options });
      if (url.endsWith('/pulls/177')) {
        return responseFor({ state: 'closed', base: { ref: 'release' }, head: { sha: headSha } });
      }
      if (url.endsWith(`/statuses/${headSha}`)) return responseFor({});
      throw new Error(`Unexpected API URL: ${url}`);
    },
  });

  assert.deepEqual(targets, [{ number: 177, head_sha: headSha }]);
  assert.ok(calls.some((call) => call.options.method === 'POST'),
    'deletion revocation must persist even if the PR is closed or temporarily targets another base');
});

test('review events preserve a fallback head SHA while scheduled discovery selects open main PR heads', async () => {
  const repository = { owner: 'SilentSaint', repo: 'pesonal-accouts-app' };
  const calls = [];
  const responseFor = (json) => ({ ok: true, json: async () => json, headers: { get: () => null } });
  const targeted = await selectPullRequestTargets({
    eventName: 'pull_request_review',
    payload: { pull_request: { number: 177, head: { sha: headSha } } },
    repository,
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl: async () => { throw new Error('targeted events must not enumerate other PRs'); },
  });
  assert.deepEqual(targeted, [{ number: 177, head_sha: headSha }]);

  const scheduled = await selectPullRequestTargets({
    eventName: 'schedule',
    payload: {},
    repository,
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl: async (url) => {
      calls.push(url);
      return responseFor([
        { number: 177, head: { sha: headSha } },
        { number: 179, head: { sha: otherSha } },
      ]);
    },
  });
  assert.deepEqual(scheduled, [
    { number: 177, head_sha: headSha },
    { number: 179, head_sha: otherSha },
  ]);
  assert.deepEqual(calls, [
    'https://api.github.com/repos/SilentSaint/pesonal-accouts-app/pulls?state=open&base=main&per_page=100',
  ]);

  const issueComment = await selectPullRequestTargets({
    eventName: 'issue_comment',
    payload: { issue: { number: 177 } },
    repository,
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl: async () => { throw new Error('issue comments must not enumerate PRs'); },
  });
  assert.deepEqual(issueComment, []);

  const issueCommentPR = await selectPullRequestTargets({
    eventName: 'issue_comment',
    payload: { issue: { number: 177, pull_request: { url: 'https://api.github.com/repos/SilentSaint/pesonal-accouts-app/pulls/177' } } },
    repository,
    apiBaseUrl: 'https://api.github.com',
    token: 'test-token',
    fetchImpl: async (url) => {
      assert.equal(url, 'https://api.github.com/repos/SilentSaint/pesonal-accouts-app/pulls/177');
      return responseFor({ number: 177, head: { sha: headSha } });
    },
  });
  assert.deepEqual(issueCommentPR, [{ number: 177, head_sha: headSha }]);
});
