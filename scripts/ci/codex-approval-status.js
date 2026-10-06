#!/usr/bin/env node
'use strict';

const fs = require('node:fs');

const STATUS_CONTEXT = 'codex-approval';
const DEFAULT_BOT_LOGIN = 'chatgpt-codex-connector[bot]';
const REVIEW_REQUEST_MARKER = /<!--\s*codex-review-request:\s*head=([a-f0-9]{40});\s*cycle=(\d+)\s*-->/gi;
const REVIEWED_SHA = /reviewed\s+(?:head|commit)(?:\s+sha)?\s*:\s*\*{0,2}\s*`?([a-f0-9]{7,40})`?/gi;

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
  const text = String(body || '');
  const approvals = [
    /\b(?:didn't|did not) find (?:any )?(?:(?:major|significant|blocking) )?issues?\b/i,
    /\bno (?:(?:major|significant|blocking|open|actionable) )?issues?\b/i,
    /\bno (?:actionable )?findings?\b/i,
    /\bnothing major to address\b/i,
    /\b(?:don't|do not) see any issues?\b/i,
    /\bLGTM\b/i,
    /\blooks good to me\b/i,
    /\bapproved\b/i,
    /\bI approve\b/i,
  ];
  const contrary = [
    /\b(?:but|however|although|except(?:\s+for)?|unless|apart from|aside from|caveat|conditional(?:ly)?|actionable|concern|caution|nit(?:pick)?|suggest(?:ion|ed|ing)?|recommend(?:ation|ed|s)?|consider|optional(?:ly)?|request changes|changes requested|not ready|not approved|do not approve|don't approve|cannot approve|can't approve|must fix|please (?:fix|change|add|remove)|should (?:fix|change|add|remove)|needs? (?:to be fixed|a fix)|issue remains|finding remains|blocker remains|edge case|follow[- ]?up|limitation|warning|todo|improv(?:e|ement|ements)|might want|could (?:you|we)|would (?:be nice|recommend)|if (?:you|we|the (?:author|PR|change))|only if)\b/i,
    /\b(?:issue|finding|problem|risk|bug|defect|regression)s?\b/i,
  ];
  const matchedApprovals = approvals.filter((pattern) => pattern.test(text));
  if (matchedApprovals.length === 0) return false;
  // "Actionable" is normally cautionary, but is part of the explicit
  // approval phrase "no actionable findings". Keep other caveats (including
  // negated approvals such as "not approved") fail-closed.
  const textWithoutNoFindingsPhrase = text.replace(/\bno actionable findings?\b/gi, ' ');
  if (contrary[0].test(textWithoutNoFindingsPhrase)) return false;
  const remainingText = matchedApprovals.reduce((remainder, pattern) => remainder.replace(pattern, ' '), text);
  return !contrary.some((pattern) => pattern.test(remainingText));
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

  const botComments = issueComments.filter((comment) =>
    comment.user && sameLogin(comment.user.login, botLogin)
    && !/<!--\s*codex-pull-request-review-summary\s*-->/i.test(comment.body || ''));
  const latestBotComment = sortNewestFirst(botComments)[0];
  const botReviewResponses = [
    ...botComments
      .filter((comment) => /\bcodex review\b|reviewed\s+(?:head|commit)\b/i.test(comment.body || ''))
      .map((comment) => ({
        ...comment,
        currentHead: reviewedHead(comment.body, commits, headSha),
        responseBody: comment.body,
        responseState: 'COMMENTED',
      })),
    ...submittedReviews
      .filter((review) => review.user && sameLogin(review.user.login, botLogin))
      .map((review) => ({
        ...review,
        currentHead: reviewSubmissionHeadMatches(review, commits, headSha),
        responseBody: review.body,
        responseState: String(review.state || '').toUpperCase(),
      })),
  ];
  const latestBotReview = sortNewestFirst(botReviewResponses.filter((response) => response.currentHead))[0];
  if (latestBotReview) {
    if (['CHANGES_REQUESTED', 'DISMISSED'].includes(latestBotReview.responseState)
      || !isUnambiguousApproval(latestBotReview.responseBody)) {
      return result(false, null, 'The latest current-head Codex review is not an unambiguous approval.', headSha);
    }
    const reviewTime = timestamp(latestBotReview.updated_at || latestBotReview.created_at || latestBotReview.submitted_at);
    const laterBotMessage = latestBotComment && latestBotComment.id !== latestBotReview.id
      && (timestamp(latestBotComment.updated_at || latestBotComment.created_at) ?? -1) > (reviewTime ?? -1);
    if (laterBotMessage) {
      return result(false, null, 'A newer Codex bot response supersedes the approval comment.', headSha);
    }
    const laterInlineBotComment = reviewComments.some((comment) =>
      comment.user && sameLogin(comment.user.login, botLogin)
      && (timestamp(comment.updated_at || comment.created_at) ?? -1) > (reviewTime ?? -1));
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
  return result(true, 'pr-reaction', 'The Codex thumbs-up follows exactly one recorded request for the current head.', headSha);
}

const REQUIRED_MERGE_GATES = [
  'exactHead',
  'mergeable',
  'conversationsResolved',
  'dockerGatePassed',
  'requiredChecksPassed',
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

async function currentCodexStatus(sha, repository, options) {
  const statuses = await githubPages(
    `/repos/${repository.owner}/${repository.repo}/commits/${sha}/statuses?per_page=100`,
    options,
  );
  const matching = statuses
    .filter((status) => status.context === STATUS_CONTEXT
      && status.creator && sameLogin(status.creator.login, 'github-actions[bot]'))
    .sort((left, right) => (timestamp(right.created_at) ?? -1) - (timestamp(left.created_at) ?? -1));
  return matching.length ? matching[0].state : null;
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

function parseRepository(fullName) {
  const parts = String(fullName || '').split('/');
  if (parts.length !== 2 || !parts.every(Boolean)) throw new Error('GITHUB_REPOSITORY is invalid.');
  return { owner: parts[0], repo: parts[1] };
}

async function reconcilePullRequest(number, repository, options) {
  const prPath = `/repos/${repository.owner}/${repository.repo}/pulls/${number}`;
  const pr = await githubJson(prPath, options);
  if (pr.state !== 'open' || !pr.base || pr.base.ref !== 'main' || !pr.head || !pr.head.sha) return;
  const sha = pr.head.sha;
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
  if (!scheduled) await publish('pending', 'Rechecking the current Codex approval signal.');
  try {
    const [commits, issueComments, reviewComments, reviews, pullRequestReactions] = await Promise.all([
      githubPages(`${prPath}/commits?per_page=100`, options),
      githubPages(`/repos/${repository.owner}/${repository.repo}/issues/${number}/comments?per_page=100`, options),
      githubPages(`${prPath}/comments?per_page=100`, options),
      githubPages(`${prPath}/reviews?per_page=100`, options),
      githubPages(`/repos/${repository.owner}/${repository.repo}/issues/${number}/reactions?per_page=100`, options),
    ]);
    const approval = evaluateCodexApproval({
      headSha: sha,
      commits,
      issueComments,
      reviewComments,
      reviews,
      pullRequestReactions,
    }, { botLogin: options.botLogin, allowedRequesters: [repository.owner] });
    const finalState = approval.authorized ? 'success' : 'failure';
    if (!scheduled || await currentCodexStatus(sha, repository, options) !== finalState) {
      await publish(finalState, approval.reason);
    }
  } catch (error) {
    await publish('error', 'Codex approval could not be verified; merge authorization is blocked.');
    throw error;
  }
}

async function run(env = process.env, fetchImpl = globalThis.fetch) {
  const repository = parseRepository(env.GITHUB_REPOSITORY);
  const token = env.GITHUB_TOKEN;
  if (!token) throw new Error('GITHUB_TOKEN is unavailable.');
  const apiBaseUrl = env.GITHUB_API_URL || 'https://api.github.com';
  const eventName = env.GITHUB_EVENT_NAME || '';
  const eventPath = env.GITHUB_EVENT_PATH;
  const payload = eventPath ? JSON.parse(fs.readFileSync(eventPath, 'utf8')) : {};
  const targetedNumber = eventPullRequestNumber(eventName, payload);
  const options = {
    apiBaseUrl,
    token,
    fetchImpl,
    botLogin: env.CODEX_REVIEW_BOT_LOGIN || DEFAULT_BOT_LOGIN,
    eventName,
    targetUrl: env.GITHUB_SERVER_URL && env.GITHUB_RUN_ID
      ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`
      : undefined,
  };
  const numbers = targetedNumber
    ? [targetedNumber]
    : (await githubPages(`/repos/${repository.owner}/${repository.repo}/pulls?state=open&base=main&per_page=100`, options))
      .map((pr) => pr.number);
  const failures = [];
  for (const number of numbers) {
    try {
      await reconcilePullRequest(number, repository, options);
    } catch (error) {
      failures.push(`PR #${number}: ${error.message}`);
    }
  }
  if (failures.length) throw new Error(failures.join('\n'));
}

if (require.main === module) {
  run().catch((error) => {
    process.stderr.write(`Codex approval status reconciliation failed: ${error.message}\n`);
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
};
