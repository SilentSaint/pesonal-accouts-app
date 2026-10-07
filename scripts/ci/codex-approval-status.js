#!/usr/bin/env node
'use strict';

const fs = require('node:fs');

const STATUS_CONTEXT = 'codex-approval';
const DEFAULT_BOT_LOGIN = 'chatgpt-codex-connector[bot]';
const DELETED_FEEDBACK_DESCRIPTION = 'Codex review feedback was deleted; a fresh review is required.';
const REVIEW_REQUEST_MARKER = /<!--\s*codex-review-request:\s*head=([a-f0-9]{40});\s*cycle=(\d+)\s*-->/gi;
const REVIEWED_SHA = /reviewed\s+(?:head|commit)(?:\s+sha)?\s*:\s*\*{0,2}\s*`?([a-f0-9]{7,40})`?/gi;
const PULL_REQUEST_REVIEWS_QUERY = `
  query PullRequestApprovalReviews($owner: String!, $repo: String!, $number: Int!, $after: String) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviews(first: 100, after: $after) {
          nodes {
            fullDatabaseId
            author { login }
            body
            state
            commit { oid }
            submittedAt
            updatedAt
            lastEditedAt
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  }
`;

function result(authorized, signal, reason, headSha = null) {
  return { authorized, signal, reason, headSha: /^[a-f0-9]{40}$/i.test(headSha || '') ? headSha : null };
}

function timestamp(value) {
  const parsed = Date.parse(value || '');
  return Number.isFinite(parsed) ? parsed : null;
}

function sameLogin(left, right) {
  return typeof left === 'string' && typeof right === 'string'
    && left.toLowerCase() === right.toLowerCase();
}

function sortNewestFirst(items) {
  return [...items].sort((left, right) => {
    const timeDifference = (timestamp(right.updated_at || right.created_at || right.submitted_at) ?? -1)
      - (timestamp(left.updated_at || left.created_at || left.submitted_at) ?? -1);
    if (timeDifference !== 0) return timeDifference;
    return Number(right.id || 0) - Number(left.id || 0);
  });
}

function activityIsNewer(candidate, reference) {
  if (candidate.id !== undefined && reference.id !== undefined
    && String(candidate.id) === String(reference.id)) return false;
  const candidateTime = timestamp(candidate.updated_at || candidate.created_at || candidate.submitted_at);
  const referenceTime = timestamp(reference.updated_at || reference.created_at || reference.submitted_at);
  if (candidateTime === null || referenceTime === null) return true;
  if (candidateTime !== referenceTime) return candidateTime > referenceTime;
  if (candidate.source !== reference.source) return true;
  const candidateId = Number(candidate.id);
  const referenceId = Number(reference.id);
  if (!Number.isSafeInteger(candidateId) || !Number.isSafeInteger(referenceId)) return true;
  return candidateId > referenceId;
}

function reviewedHead(body, commits, headSha) {
  const matches = [...String(body || '').matchAll(REVIEWED_SHA)];
  if (matches.length !== 1) return false;
  const prefix = matches[0][1].toLowerCase();
  const matchingCommits = commits.filter((commit) =>
    typeof commit.sha === 'string' && commit.sha.toLowerCase().startsWith(prefix));
  return matchingCommits.length === 1 && matchingCommits[0].sha.toLowerCase() === headSha.toLowerCase();
}

function reviewSubmissionHeadMatches(review, commits, headSha) {
  if (typeof review.commit_id !== 'string' || review.commit_id.toLowerCase() !== headSha.toLowerCase()) return false;
  const body = String(review.body || '');
  return !/\breviewed\s+(?:head|commit)\b/i.test(body) || reviewedHead(body, commits, headSha);
}

function isUnambiguousApproval(body) {
  const text = String(body || '').replace(
    /<details>\s*<summary>\s*ℹ️ About Codex in GitHub<\/summary>[\s\S]*$/i,
    ' ',
  ).replace(/^\s*(?:#{1,6}\s*)?(?:💡\s*)?Codex Review\s*:?\s*/i, ' ')
    .replace(/^[ \t]*\*{0,2}Reviewed commit(?:\s+sha)?\s*:\s*\*{0,2}[ \t]*`?[a-f0-9]{7,40}`?[ \t]*$/gim, ' ');
  const negatedApproval = /\b(?:not|never|isn't|aren't|wasn't|weren't|don't|doesn't|didn't|can't|cannot|won't|wouldn't)\b(?:\W+\w+){0,6}\W+\b(?:lgtm|approv(?:e|ed|al|ing)|looks?\s+good|good\s+to\s+merge|ready\s+to\s+merge)\b/i;
  if (negatedApproval.test(text)) return false;
  const approvals = [
    /\bI approve (?:this|the) (?:PR|pull request)\b/i,
    /\bthis (?:PR|pull request) is approved\b/i,
    /\bthis is approved\b/i,
    /\b(?:didn't|did not) find (?:any )?(?:(?:major|significant|blocking) )?issues?\b/i,
    /\bno (?:(?:major|significant|blocking|open|actionable) )?issues?(?:\s+(?:(?:have|were|are)(?:\s+been)?\s+)?found)?\b/i,
    /\bno (?:actionable )?findings?(?:\s+(?:(?:have|were|are)(?:\s+been)?\s+)?found)?\b/i,
    /\bnothing major to address\b/i,
    /\b(?:don't|do not) see any issues?\b/i,
    /\bLGTM\b/i,
    /\blooks good to me\b/i,
    /\bapproved\b/i,
    /\bI approve\b/i,
  ];
  const contrary = [
    /\b(?:but|however|although|except(?:\s+for)?|unless|apart from|aside from|caveat|conditional(?:ly)?|actionable|concern|caution|nit(?:pick)?|suggest(?:ion|ed|ing)?|recommend(?:ation|ed|s)?|consider|optional(?:ly)?|request changes|changes requested|not ready|not approved|do not approve|don't approve|cannot approve|can't approve|must fix|please (?:fix|change|add|remove)|should (?:fix|change|add|remove)|needs? (?:to be fixed|a fix)|issue remains|finding remains|blocker remains|edge case|follow[- ]?up|limitation|warning|todo|improv(?:e|ement|ements)|might want|could (?:you|we)|would (?:be nice|recommend)|if (?:you|we|the (?:author|PR|change))|only if)\b|\b(?:not|never)\s+(?:clearly\s+)?(?:lgtm|approved|approve|an?\s+approval|ready to merge|good to merge)\b/i,
    /\b(?:issue|finding|problem|risk|bug|defect|regression)s?\b/i,
  ];
  const matchedApprovals = approvals.filter((pattern) => pattern.test(text));
  if (matchedApprovals.length === 0) return false;
  const conditional = /\b(?:if|unless|when|provided(?:\s+that)?|pending|assuming(?:\s+that)?|subject\s+to|contingent(?:\s+on)?|depending\s+on|until|once|after)\b/i;
  if (conditional.test(text)) return false;
  // "Actionable" is normally cautionary, but is part of the explicit
  // approval phrase "no actionable findings". Keep other caveats (including
  // negated approvals such as "not approved") fail-closed.
  const textWithoutNoFindingsPhrase = text.replace(/\bno actionable findings?\b/gi, ' ');
  if (contrary[0].test(textWithoutNoFindingsPhrase)) return false;
  const remainingText = matchedApprovals.reduce((remainder, pattern) => remainder.replace(pattern, ' '), text);
  const nonSubstantiveRemainder = /^(?:(?:keep it up|nice work|hooray|great work|great job|well done|thanks|thank you)|[\s.,;:!?…—–\-*_`#>👍👏✨✅])*$/i;
  return !contrary.some((pattern) => pattern.test(remainingText))
    && nonSubstantiveRemainder.test(remainingText);
}

function recordedRequests(issueComments, headSha, allowedRequesters) {
  const requests = [];
  for (const comment of issueComments) {
    const login = comment.user && comment.user.login;
    if (!allowedRequesters.some((allowed) => sameLogin(login, allowed))) continue;
    const body = String(comment.body || '');
    if (!/@codex\s+review\b/i.test(body)) continue;
    for (const match of body.matchAll(REVIEW_REQUEST_MARKER)) {
      if (match[1].toLowerCase() !== headSha.toLowerCase()) continue;
      const cycle = Number(match[2]);
      if (!Number.isInteger(cycle) || cycle < 1 || cycle > 10) continue;
      const requestTime = timestamp(comment.updated_at || comment.created_at);
      if (requestTime === null) continue;
      requests.push({ id: comment.id, headSha: match[1], cycle, createdAt: requestTime });
    }
  }
  return requests;
}

/**
 * Evaluates the GitHub snapshot used by the required codex-approval status.
 * This policy only grants the Codex signal; mergeability, local validation,
 * branch protection, required checks, and serialization are independent gates.
 */
function evaluateCodexApproval(snapshot, options = {}) {
  const headSha = snapshot && snapshot.headSha;
  const commits = Array.isArray(snapshot && snapshot.commits) ? snapshot.commits : [];
  const issueComments = Array.isArray(snapshot && snapshot.issueComments) ? snapshot.issueComments : [];
  const reviewComments = Array.isArray(snapshot && snapshot.reviewComments) ? snapshot.reviewComments : [];
  const submittedReviews = Array.isArray(snapshot && snapshot.reviews) ? snapshot.reviews : [];
  const reactions = Array.isArray(snapshot && snapshot.pullRequestReactions)
    ? snapshot.pullRequestReactions
    : [];
  const botLogin = options.botLogin || DEFAULT_BOT_LOGIN;
  const allowedRequesters = options.allowedRequesters || ['SilentSaint'];

  if (!/^[a-f0-9]{40}$/i.test(headSha || '')) {
    return result(false, null, 'The current PR head SHA is missing or invalid.', headSha);
  }
  if (!commits.some((commit) => commit.sha && commit.sha.toLowerCase() === headSha.toLowerCase())) {
    return result(false, null, 'The current head could not be verified in the PR commit list.', headSha);
  }
  if (isDeletedCodexFeedback(options.eventName, options.eventPayload || {}, botLogin)) {
    return result(false, null, DELETED_FEEDBACK_DESCRIPTION, headSha);
  }

  const feedbackRevokedAt = timestamp(options.revokedAt);

  const botComments = issueComments.filter((comment) =>
    comment.user && sameLogin(comment.user.login, botLogin)
    && !/<!--\s*codex-pull-request-review-summary\s*-->/i.test(comment.body || ''))
    .map((comment) => ({ ...comment, source: 'issue-comment' }));
  const latestBotComment = sortNewestFirst(botComments)[0];
  const botReviewResponses = [
    ...botComments
      .filter((comment) => /\bcodex review\b|reviewed\s+(?:head|commit)\b/i.test(comment.body || ''))
      .map((comment) => ({
        ...comment,
        source: 'issue-comment',
        currentHead: reviewedHead(comment.body, commits, headSha),
        responseBody: comment.body,
        responseState: 'COMMENTED',
      })),
    ...submittedReviews
      .filter((review) => review.user && sameLogin(review.user.login, botLogin))
      .map((review) => ({
        ...review,
        source: 'pull-request-review',
        currentHead: reviewSubmissionHeadMatches(review, commits, headSha),
        responseBody: review.body,
        responseState: String(review.state || '').toUpperCase(),
      })),
  ];
  const latestBotReview = sortNewestFirst(botReviewResponses)[0];
  if (latestBotReview) {
    const latestReviewTime = timestamp(
      latestBotReview.updated_at || latestBotReview.created_at || latestBotReview.submitted_at,
    );
    const crossResourceTimestampTie = botReviewResponses.some((response) =>
      response.source !== latestBotReview.source
      && timestamp(response.updated_at || response.created_at || response.submitted_at) === latestReviewTime);
    if (crossResourceTimestampTie) {
      return result(false, null, 'Codex review activity has an ambiguous cross-resource timestamp tie.', headSha);
    }
    const unsubmittedReview = latestBotReview.source === 'pull-request-review'
      && (!['COMMENTED', 'APPROVED'].includes(latestBotReview.responseState)
        || timestamp(latestBotReview.submitted_at) === null);
    if (!latestBotReview.currentHead
      || unsubmittedReview
      || ['CHANGES_REQUESTED', 'DISMISSED'].includes(latestBotReview.responseState)
      || !isUnambiguousApproval(latestBotReview.responseBody)) {
      return result(false, null, 'The latest Codex review is not an unambiguous current-head approval.', headSha);
    }
    const latestReviewResponseTime = timestamp(
      latestBotReview.updated_at || latestBotReview.created_at || latestBotReview.submitted_at,
    );
    if (feedbackRevokedAt !== null
      && (latestReviewResponseTime === null || latestReviewResponseTime <= feedbackRevokedAt)) {
      return result(false, null, 'The latest Codex review predates deleted-feedback revocation; a fresh review is required.', headSha);
    }
    const laterBotMessage = latestBotComment && latestBotComment.id !== latestBotReview.id
      && activityIsNewer(latestBotComment, latestBotReview);
    if (laterBotMessage) {
      return result(false, null, 'A newer Codex bot response supersedes the approval comment.', headSha);
    }
    const laterInlineBotComment = reviewComments.some((comment) =>
      comment.user && sameLogin(comment.user.login, botLogin)
      && activityIsNewer({ ...comment, source: 'review-comment' }, latestBotReview));
    if (laterInlineBotComment) {
      return result(false, null, 'A newer inline Codex review comment requires fresh review resolution.', headSha);
    }
    return result(true, 'review-comment', 'The latest Codex review clearly approves the current head.', headSha);
  }

  const requests = recordedRequests(issueComments, headSha, allowedRequesters);
  if (requests.length !== 1) {
    return result(false, null, 'A PR-level reaction requires exactly one recorded request for the current head.', headSha);
  }
  const request = requests[0];
  const reviewAfterRequest = botComments.some((comment) =>
    (timestamp(comment.updated_at || comment.created_at) ?? -1) >= request.createdAt)
    || submittedReviews.some((review) =>
      review.user && sameLogin(review.user.login, botLogin)
      && (timestamp(review.updated_at || review.submitted_at) ?? -1) >= request.createdAt);
  if (reviewAfterRequest) {
    return result(false, null, 'A newer Codex review response must be evaluated instead of a reaction.', headSha);
  }
  const inlineAfterRequest = reviewComments.some((comment) =>
    comment.user && sameLogin(comment.user.login, botLogin)
    && (timestamp(comment.updated_at || comment.created_at) ?? -1) >= request.createdAt);
  if (inlineAfterRequest) {
    return result(false, null, 'An inline Codex review response followed the recorded request.', headSha);
  }
  const thumbsUps = reactions.filter((reaction) =>
    reaction.content === '+1' && reaction.user && sameLogin(reaction.user.login, botLogin));
  if (thumbsUps.length !== 1) {
    return result(false, null, 'Exactly one PR-level Codex thumbs-up is required.', headSha);
  }
  const reactionTime = timestamp(thumbsUps[0].created_at);
  if (reactionTime === null || reactionTime <= request.createdAt) {
    return result(false, null, 'The Codex thumbs-up did not follow the current-head review request.', headSha);
  }
  if (feedbackRevokedAt !== null && reactionTime <= feedbackRevokedAt) {
    return result(false, null, 'The Codex thumbs-up predates deleted-feedback revocation; a fresh review is required.', headSha);
  }
  return result(true, 'pr-reaction', 'The Codex thumbs-up follows exactly one recorded request for the current head.', headSha);
}

const REQUIRED_MERGE_GATES = [
  'exactHead',
  'mergeable',
  'conversationsResolved',
  'dockerGatePassed',
  'requiredChecksPassed',
  'codexReconciliationSucceeded',
  'branchCurrent',
  'serverEnforcementVerified',
  'serializationVerified',
  'maintainerApprovalSatisfied',
];

function decideAgentMerge({ approval, gates, expectedHeadSha } = {}) {
  const failedGates = [];
  if (!approval || approval.authorized !== true || approval.headSha !== expectedHeadSha
    || !/^[a-f0-9]{40}$/i.test(expectedHeadSha || '')) {
    failedGates.push('codexApproval');
  }
  for (const gate of REQUIRED_MERGE_GATES) {
    if (!gates || gates[gate] !== true) failedGates.push(gate);
  }
  return { allowed: failedGates.length === 0, failedGates };
}

async function publishCommitStatus({
  apiBaseUrl = 'https://api.github.com',
  owner,
  repo,
  sha,
  state,
  description,
  targetUrl,
  token,
  fetchImpl = globalThis.fetch,
}) {
  if (!/^[a-f0-9]{40}$/i.test(sha || '')) throw new Error('Refusing to publish status without a full commit SHA.');
  if (!['error', 'failure', 'pending', 'success'].includes(state)) throw new Error('Invalid commit status state.');
  if (!owner || !repo || !token || typeof fetchImpl !== 'function') throw new Error('GitHub status configuration is incomplete.');
  const url = `${apiBaseUrl.replace(/\/$/, '')}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/statuses/${sha}`;
  const response = await fetchImpl(url, {
    method: 'POST',
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'X-GitHub-Api-Version': '2022-11-28',
    },
    body: JSON.stringify({
      state,
      context: STATUS_CONTEXT,
      description: String(description || 'Codex approval not verified.').slice(0, 140),
      ...(targetUrl ? { target_url: targetUrl } : {}),
    }),
  });
  if (!response.ok) throw new Error(`GitHub rejected the ${STATUS_CONTEXT} status update (${response.status}).`);
  return response.json();
}

function apiUrl(path, baseUrl) {
  return `${baseUrl.replace(/\/$/, '')}${path}`;
}

async function githubJson(path, { apiBaseUrl, token, fetchImpl }) {
  const response = await fetchImpl(apiUrl(path, apiBaseUrl), {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  if (!response.ok) throw new Error(`GitHub API read failed (${response.status}) for ${path}.`);
  return response.json();
}

function graphqlEndpoint(apiBaseUrl) {
  const endpoint = new URL(apiBaseUrl);
  const apiPath = endpoint.pathname.replace(/\/+$/, '');
  endpoint.pathname = apiPath.endsWith('/api/v3')
    ? apiPath.replace(/\/v3$/, '/graphql')
    : `${apiPath}/graphql`;
  endpoint.search = '';
  endpoint.hash = '';
  return endpoint.toString();
}

async function githubGraphql(query, variables, options) {
  const response = await options.fetchImpl(graphqlEndpoint(options.apiBaseUrl), {
    method: 'POST',
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${options.token}`,
      'X-GitHub-Api-Version': '2022-11-28',
    },
    body: JSON.stringify({ query, variables }),
  });
  if (!response.ok) throw new Error(`GitHub API read failed (${response.status}) for the pull-request review query.`);
  const payload = await response.json();
  if (!payload || !payload.data || (Array.isArray(payload.errors) && payload.errors.length > 0)) {
    throw new Error('GitHub GraphQL returned an incomplete pull-request review response.');
  }
  return payload.data;
}

async function pullRequestReviews(number, repository, options) {
  const reviews = [];
  let after = null;
  while (true) {
    const data = await githubGraphql(PULL_REQUEST_REVIEWS_QUERY, {
      owner: repository.owner,
      repo: repository.repo,
      number,
      after,
    }, options);
    const connection = data.repository && data.repository.pullRequest && data.repository.pullRequest.reviews;
    if (!connection || !Array.isArray(connection.nodes) || !connection.pageInfo) {
      throw new Error('GitHub GraphQL returned an invalid pull-request review list.');
    }
    for (const review of connection.nodes) {
      if (!review || review.fullDatabaseId === null || review.fullDatabaseId === undefined) {
        throw new Error('GitHub GraphQL returned a review without a stable database ID.');
      }
      reviews.push({
        id: review.fullDatabaseId,
        user: review.author ? { login: review.author.login } : null,
        body: review.body,
        state: review.state,
        commit_id: review.commit ? review.commit.oid : null,
        submitted_at: review.submittedAt,
        updated_at: review.lastEditedAt || review.updatedAt || review.submittedAt,
      });
    }
    if (typeof connection.pageInfo.hasNextPage !== 'boolean') {
      throw new Error('GitHub GraphQL returned invalid pull-request review pagination state.');
    }
    if (!connection.pageInfo.hasNextPage) break;
    if (!connection.pageInfo.endCursor || connection.pageInfo.endCursor === after) {
      throw new Error('GitHub GraphQL returned an invalid pull-request review pagination cursor.');
    }
    after = connection.pageInfo.endCursor;
  }
  return reviews;
}

async function githubPages(path, options) {
  const items = [];
  let next = path;
  while (next) {
    const response = await options.fetchImpl(apiUrl(next, options.apiBaseUrl), {
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${options.token}`,
        'X-GitHub-Api-Version': '2022-11-28',
      },
    });
    if (!response.ok) throw new Error(`GitHub API read failed (${response.status}) for ${next}.`);
    const page = await response.json();
    if (!Array.isArray(page)) throw new Error(`GitHub API returned an invalid list for ${next}.`);
    items.push(...page);
    const link = response.headers && response.headers.get('link');
    const nextLink = link && link.split(',').map((part) => part.trim()).find((part) => /rel="next"/.test(part));
    const url = nextLink && nextLink.match(/<([^>]+)>/);
    next = url ? url[1] : null;
    if (next) {
      const parsed = new URL(next);
      if (parsed.origin !== new URL(options.apiBaseUrl).origin) throw new Error('Refusing a cross-origin GitHub pagination link.');
      next = `${parsed.pathname}${parsed.search}`;
    }
  }
  return items;
}

async function currentCodexStatuses(sha, repository, options) {
  return githubPages(
    `/repos/${repository.owner}/${repository.repo}/commits/${sha}/statuses?per_page=100`,
    options,
  );
}

function trustedCodexStatuses(statuses) {
  return statuses
    .filter((status) => status.context === STATUS_CONTEXT
      && status.creator && sameLogin(status.creator.login, 'github-actions[bot]'))
    .sort((left, right) => (timestamp(right.created_at) ?? -1) - (timestamp(left.created_at) ?? -1));
}

function latestDeletedFeedbackRevocation(statuses) {
  const marker = trustedCodexStatuses(statuses)
    .find((status) => status.state === 'failure'
      && status.description === DELETED_FEEDBACK_DESCRIPTION
      && timestamp(status.created_at) !== null);
  return marker ? marker.created_at : null;
}

function eventPullRequestNumber(eventName, payload) {
  if (eventName === 'issue_comment') {
    return payload.issue && payload.issue.pull_request ? payload.issue.number : null;
  }
  if (eventName === 'pull_request' || eventName === 'pull_request_target'
    || eventName === 'pull_request_review' || eventName === 'pull_request_review_comment') {
    return payload.pull_request && payload.pull_request.number;
  }
  return null;
}

function isDeletedCodexFeedback(eventName, payload, botLogin) {
  if (payload.action !== 'deleted'
    || !['issue_comment', 'pull_request_review_comment'].includes(eventName)
    || !Number.isSafeInteger(eventPullRequestNumber(eventName, payload))) return false;
  return Boolean(payload.comment && payload.comment.user
    && sameLogin(payload.comment.user.login, botLogin));
}

function parseRepository(fullName) {
  const parts = String(fullName || '').split('/');
  if (parts.length !== 2 || !parts.every(Boolean)) throw new Error('GITHUB_REPOSITORY is invalid.');
  return { owner: parts[0], repo: parts[1] };
}

async function selectPullRequestTargets({
  eventName,
  payload = {},
  repository,
  apiBaseUrl = 'https://api.github.com',
  token,
  botLogin = DEFAULT_BOT_LOGIN,
  fetchImpl = globalThis.fetch,
} = {}) {
  const targetedNumber = eventPullRequestNumber(eventName, payload);
  if (Number.isSafeInteger(targetedNumber) && targetedNumber > 0) {
    let headSha = payload.pull_request && payload.pull_request.head && payload.pull_request.head.sha;
    if (isDeletedCodexFeedback(eventName, payload, botLogin)) {
      if (!repository || !repository.owner || !repository.repo || !token) {
        throw new Error('Deleted feedback revocation configuration is incomplete.');
      }
      const pullRequest = await githubJson(
        `/repos/${repository.owner}/${repository.repo}/pulls/${targetedNumber}`,
        { apiBaseUrl, token, fetchImpl },
      );
      headSha = pullRequest.head && pullRequest.head.sha;
      if (!/^[a-f0-9]{40}$/i.test(headSha || '')) {
        throw new Error('Deleted feedback revocation head SHA is missing or invalid.');
      }
      await publishCommitStatus({
        apiBaseUrl,
        owner: repository.owner,
        repo: repository.repo,
        sha: headSha,
        state: 'failure',
        description: DELETED_FEEDBACK_DESCRIPTION,
        token,
        fetchImpl,
      });
      return [{ number: targetedNumber, head_sha: headSha }];
    }
    if (!/^[a-f0-9]{40}$/i.test(headSha || '')) {
      if (!repository || !repository.owner || !repository.repo || !token) {
        throw new Error('Pull-request target head could not be verified.');
      }
      const pullRequest = await githubJson(
        `/repos/${repository.owner}/${repository.repo}/pulls/${targetedNumber}`,
        { apiBaseUrl, token, fetchImpl },
      );
      headSha = pullRequest.head && pullRequest.head.sha;
    }
    if (!/^[a-f0-9]{40}$/i.test(headSha || '')) {
      throw new Error('Pull-request target head SHA is missing or invalid.');
    }
    return [{ number: targetedNumber, head_sha: headSha }];
  }
  if (eventName === 'issue_comment') return [];
  if (!['schedule', 'workflow_dispatch'].includes(eventName)) return [];
  if (!repository || !repository.owner || !repository.repo || !token) {
    throw new Error('Pull-request discovery configuration is incomplete.');
  }
  const pullRequests = await githubPages(
    `/repos/${repository.owner}/${repository.repo}/pulls?state=open&base=main&per_page=100`,
    { apiBaseUrl, token, fetchImpl },
  );
  return pullRequests
    .filter((pullRequest) => Number.isSafeInteger(pullRequest.number) && pullRequest.number > 0)
    .map((pullRequest) => {
      const headSha = pullRequest.head && pullRequest.head.sha;
      if (!/^[a-f0-9]{40}$/i.test(headSha || '')) {
        throw new Error(`Pull-request target ${pullRequest.number} has no verified head SHA.`);
      }
      return { number: pullRequest.number, head_sha: headSha };
    });
}

async function reconcilePullRequest(number, repository, options) {
  const prPath = `/repos/${repository.owner}/${repository.repo}/pulls/${number}`;
  let sha = /^[a-f0-9]{40}$/i.test(options.headSha || '') ? options.headSha : null;
  const publish = (state, description) => publishCommitStatus({
    apiBaseUrl: options.apiBaseUrl,
    owner: repository.owner,
    repo: repository.repo,
    sha,
    state,
    description,
    targetUrl: options.targetUrl,
    token: options.token,
    fetchImpl: options.fetchImpl,
  });

  // Event-driven revocation first withdraws any old green result. Scheduled
  // reconciliation compares the final state before writing to avoid creating
  // two status records every five minutes for unchanged PRs.
  const scheduled = options.eventName === 'schedule';
  let pendingAttempted = false;
  try {
    const pr = await githubJson(prPath, options);
    if (pr.state !== 'open' || !pr.base || pr.base.ref !== 'main') return;
    const liveSha = pr.head && pr.head.sha;
    if (!/^[a-f0-9]{40}$/i.test(liveSha || '')) {
      throw new Error('The current PR head SHA is missing or invalid.');
    }
    sha = liveSha;
    const priorStatuses = await currentCodexStatuses(sha, repository, options);
    const latestStatus = trustedCodexStatuses(priorStatuses)[0] || null;
    const revokedAt = latestDeletedFeedbackRevocation(priorStatuses);
    if (!scheduled) {
      pendingAttempted = true;
      await publish('pending', 'Rechecking the current Codex approval signal.');
    }
    const [commits, issueComments, reviewComments, reviews, pullRequestReactions] = await Promise.all([
      githubPages(`${prPath}/commits?per_page=100`, options),
      githubPages(`/repos/${repository.owner}/${repository.repo}/issues/${number}/comments?per_page=100`, options),
      githubPages(`${prPath}/comments?per_page=100`, options),
      pullRequestReviews(number, repository, options),
      githubPages(`/repos/${repository.owner}/${repository.repo}/issues/${number}/reactions?per_page=100`, options),
    ]);
    const approval = evaluateCodexApproval({
      headSha: sha,
      commits,
      issueComments,
      reviewComments,
      reviews,
      pullRequestReactions,
    }, {
      botLogin: options.botLogin,
      allowedRequesters: [repository.owner],
      eventName: options.eventName,
      eventPayload: options.eventPayload,
      revokedAt,
    });
    const finalState = approval.authorized ? 'success' : 'failure';
    if (!scheduled || !latestStatus || latestStatus.state !== finalState) {
      await publish(finalState, approval.reason);
    }
  } catch (error) {
    if (sha) {
      if (!scheduled && !pendingAttempted) {
        pendingAttempted = true;
        await publish('pending', 'Rechecking the current Codex approval signal.');
      }
      await publish('error', 'Codex approval could not be verified; merge authorization is blocked.');
    }
    throw error;
  }
}

async function run(env = process.env, fetchImpl = globalThis.fetch) {
  const repository = parseRepository(env.GITHUB_REPOSITORY);
  const token = env.GITHUB_TOKEN;
  if (!token) throw new Error('GITHUB_TOKEN is unavailable.');
  const apiBaseUrl = env.GITHUB_API_URL || 'https://api.github.com';
  const eventName = env.GITHUB_EVENT_NAME || '';
  const eventPayload = env.GITHUB_EVENT_PATH
    ? JSON.parse(fs.readFileSync(env.GITHUB_EVENT_PATH, 'utf8'))
    : {};
  const number = Number(env.CODEX_PR_NUMBER);
  if (!Number.isSafeInteger(number) || number < 1) throw new Error('CODEX_PR_NUMBER is invalid.');
  const options = {
    apiBaseUrl,
    token,
    fetchImpl,
    botLogin: env.CODEX_REVIEW_BOT_LOGIN || DEFAULT_BOT_LOGIN,
    eventName,
    eventPayload,
    headSha: env.CODEX_PR_HEAD_SHA,
    targetUrl: env.GITHUB_SERVER_URL && env.GITHUB_RUN_ID
      ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`
      : undefined,
  };
  await reconcilePullRequest(number, repository, options);
}

if (require.main === module) {
  const selectTargets = process.argv.includes('--select-pr-targets');
  const operation = selectTargets
    ? (async () => {
      const repository = parseRepository(process.env.GITHUB_REPOSITORY);
      const eventPath = process.env.GITHUB_EVENT_PATH;
      const payload = eventPath ? JSON.parse(fs.readFileSync(eventPath, 'utf8')) : {};
      const targets = await selectPullRequestTargets({
        eventName: process.env.GITHUB_EVENT_NAME || '',
        payload,
        repository,
        apiBaseUrl: process.env.GITHUB_API_URL || 'https://api.github.com',
        token: process.env.GITHUB_TOKEN,
        botLogin: process.env.CODEX_REVIEW_BOT_LOGIN || DEFAULT_BOT_LOGIN,
      });
      const output = `pr_targets=${JSON.stringify(targets)}\n`;
      if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, output);
      else process.stdout.write(output);
    })()
    : run();
  operation.catch((error) => {
    const description = selectTargets ? 'Codex PR target selection' : 'Codex approval status reconciliation';
    process.stderr.write(`${description} failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = {
  STATUS_CONTEXT,
  decideAgentMerge,
  evaluateCodexApproval,
  isUnambiguousApproval,
  publishCommitStatus,
  reconcilePullRequest,
  reviewedHead,
  selectPullRequestTargets,
};
