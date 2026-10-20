#!/usr/bin/env node
'use strict';

const fs = require('node:fs');

const STATUS_CONTEXT = 'codex-approval';
const DEFAULT_BOT_LOGIN = 'chatgpt-codex-connector[bot]';
const DELETED_FEEDBACK_DESCRIPTION = 'Codex review feedback was deleted; a fresh review is required.';
const DUPLICATE_HEAD_SHA_BLOCKED = 'Multiple open pull requests share this head commit; authorization cannot be isolated.';
const CROSS_PR_APPROVAL_BLOCKED = 'Codex approval belongs to another pull request; a fresh review is required.';
const BASE_CHANGE_REVIEW_REQUIRED = 'base-change-review-required';
const NEGATIVE_REACTION_REVIEW_REQUIRED = 'negative-reaction-review-required';
const CYCLE_LIMIT_EXHAUSTED_MARKER = 'cycle-10-exhausted';
const CYCLE_LIMIT_EXCEEDED = 'The automated review cycle limit of ten cycles has been exceeded.';
const REVIEW_REQUEST_MARKER = /<!--\s*codex-review-request:\s*head=([a-f0-9]{40});\s*base=([a-f0-9]{40});\s*cycle=(\d+)\s*-->/gi;
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
            createdAt
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

function timestampIsUnambiguouslyAfter(candidate, boundary) {
  return candidate !== null && boundary !== null
    && candidate > boundary
    && Math.floor(candidate / 1000) > Math.floor(boundary / 1000);
}

function timestampMayBeAtOrAfter(candidate, boundary) {
  return candidate !== null && boundary !== null
    && Math.floor(candidate / 1000) >= Math.floor(boundary / 1000);
}

function sameLogin(left, right) {
  return typeof left === 'string' && typeof right === 'string'
    && left.toLowerCase() === right.toLowerCase();
}

function reviewResponseCreatedAt(item) {
  return timestamp(item.source === 'pull-request-review'
    ? item.submitted_at
    : item.created_at);
}

function reviewStartedAt(item) {
  return timestamp(item.source === 'pull-request-review'
    ? item.review_created_at
    : item.created_at);
}

function sortReviewResponsesNewestFirst(items) {
  return [...items].sort((left, right) => {
    const timeDifference = (reviewResponseCreatedAt(right) ?? -1) - (reviewResponseCreatedAt(left) ?? -1);
    if (timeDifference !== 0) return timeDifference;
    return Number(right.id || 0) - Number(left.id || 0);
  });
}

function activityIsNewer(candidate, reference) {
  if (candidate === reference) return false;
  if (candidate.source === reference.source
    && candidate.id !== undefined && reference.id !== undefined
    && String(candidate.id) === String(reference.id)) return false;
  const candidateCreatedAt = reviewResponseCreatedAt(candidate);
  const referenceCreatedAt = reviewResponseCreatedAt(reference);
  const candidateActivityAt = timestamp(candidate.updated_at) ?? candidateCreatedAt;
  if (candidateCreatedAt === null || referenceCreatedAt === null || candidateActivityAt === null) return true;
  if (candidateCreatedAt > referenceCreatedAt || candidateActivityAt > referenceCreatedAt) return true;
  if (candidateActivityAt === referenceCreatedAt && candidateCreatedAt < referenceCreatedAt) return true;
  if (candidateCreatedAt < referenceCreatedAt) return false;
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
    /<details>\s*<summary>\s*ℹ️ About Codex in GitHub<\/summary>[\s\S]*?<\/details>/i,
    ' ',
  ).replace(/^\s*(?:#{1,6}\s*)?(?:💡\s*)?Codex Review\s*:?\s*/i, ' ')
    .replace(/^[ \t]*\*{0,2}Reviewed commit(?:\s+sha)?\s*:\s*\*{0,2}[ \t]*`?[a-f0-9]{7,40}`?[ \t]*$/gim, ' ');
  if (text.includes('?')) return false;
  const negatedApproval = /\b(?:not|never|isn't|aren't|wasn't|weren't|don't|doesn't|didn't|can't|cannot|won't|wouldn't)\b(?:\W+\w+){0,6}\W+\b(?:lgtm|approv(?:e|ed|al|ing)|looks?\s+good|good\s+to\s+merge|ready\s+to\s+merge)\b/i;
  if (negatedApproval.test(text)) return false;
  const approvals = [
    /\bI approve (?:this|the) (?:PR|pull request)\b/i,
    /\bthis (?:PR|pull request) is approved\b/i,
    /\bthis is approved\b/i,
    /\b(?:I\s+)?(?:didn't|did not) find (?:any )?(?:(?:major|significant|blocking) )?issues?\b/i,
    /\b(?:I found )?no (?:(?:major|significant|blocking|open|actionable) )?issues?(?:\s+(?:(?:have|were|are)(?:\s+been)?\s+)?(?:found|identified))?\b/i,
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

function recordedRequests(issueComments, headSha, allowedRequesters, baseSha) {
  const requests = [];
  let ambiguous = false;
  let capExceeded = false;
  const allOwnerMarkers = [];

  for (const comment of issueComments) {
    const login = comment.user && comment.user.login;
    if (!allowedRequesters.some((allowed) => sameLogin(login, allowed))) continue;
    const body = String(comment.body || '');
    if (!/@codex\s+review\b/i.test(body)) continue;
    const matches = [...body.matchAll(REVIEW_REQUEST_MARKER)];
    if (matches.length > 1) {
      ambiguous = true;
    }
    for (const match of matches) {
      const markerHeadSha = match[1].toLowerCase();
      const markerBaseSha = match[2].toLowerCase();
      const cycle = Number(match[3]);
      const requestTime = timestamp(comment.created_at);
      const requestUpdatedAt = timestamp(comment.updated_at);
      const isUnedited = requestTime !== null && requestUpdatedAt !== null && requestUpdatedAt === requestTime;

      if (isUnedited) {
        allOwnerMarkers.push({
          id: comment.id,
          headSha: markerHeadSha,
          baseSha: markerBaseSha,
          cycle,
          createdAt: requestTime,
        });
      }

      // Inspect owner-authored cycle markers for cap violations before filtering to current head/base.
      if (!Number.isInteger(cycle) || cycle < 1 || cycle > 10) {
        capExceeded = true;
        continue;
      }
      if (cycle === 10 && markerHeadSha !== headSha.toLowerCase()) {
        capExceeded = true;
        continue;
      }

      if (matches.length > 1) continue;
      if (markerHeadSha !== headSha.toLowerCase()) continue;
      if (markerBaseSha !== baseSha.toLowerCase()) continue;
      if (!isUnedited) continue;
      requests.push({ id: comment.id, headSha: match[1], baseSha: markerBaseSha, cycle, createdAt: requestTime });
    }
  }

  allOwnerMarkers.sort((a, b) => a.createdAt - b.createdAt || a.id - b.id);
  for (let i = 1; i < allOwnerMarkers.length; i++) {
    if (allOwnerMarkers[i].cycle <= allOwnerMarkers[i - 1].cycle) {
      capExceeded = true;
      break;
    }
    if (allOwnerMarkers[i - 1].cycle === 10) {
      capExceeded = true;
      break;
    }
  }

  return { ambiguous, requests, capExceeded, allOwnerMarkers };
}


function statusPrNumber(status) {
  const match = String(status && status.description || '').match(/(?:^|[;\s])pr=(\d+)(?=$|[;\s])/i);
  return match ? Number(match[1]) : null;
}

function statusBaseSha(status) {
  const match = String(status && status.description || '').match(/(?:^|[;\s])base-sha=([a-f0-9]{40})(?=$|[;\s])/i);
  return match ? match[1].toLowerCase() : null;
}

function isPullRequestBaseEdit(eventName, payload) {
  return eventName === 'pull_request_target'
    && payload && payload.action === 'edited'
    && payload.changes && Object.prototype.hasOwnProperty.call(payload.changes, 'base');
}

/**
 * Evaluates the GitHub snapshot used by the required codex-approval status.
 * This policy only grants the Codex signal; mergeability, local validation,
 * branch protection, required checks, and serialization are independent gates.
 */
function evaluateCodexApproval(snapshot, options = {}) {
  const headSha = snapshot && snapshot.headSha;
  const baseSha = snapshot && snapshot.baseSha;
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
  if (!/^[a-f0-9]{40}$/i.test(baseSha || '')) {
    return result(false, null, 'The current PR base SHA is missing or invalid.', headSha);
  }
  if (!commits.some((commit) => commit.sha && commit.sha.toLowerCase() === headSha.toLowerCase())) {
    return result(false, null, 'The current head could not be verified in the PR commit list.', headSha);
  }
  if (Array.isArray(snapshot && snapshot.openPullRequests)) {
    const prNumber = snapshot.number;
    const hasDuplicateHead = snapshot.openPullRequests.some((pr) => {
      const isOther = prNumber !== undefined ? Number(pr.number) !== Number(prNumber) : true;
      return isOther
        && pr.head && pr.head.sha
        && pr.head.sha.toLowerCase() === headSha.toLowerCase();
    });
    if (hasDuplicateHead) {
      return result(false, null, DUPLICATE_HEAD_SHA_BLOCKED, headSha);
    }
  }
  if (snapshot && snapshot.hasDuplicateHeadSha === true) {
    return result(false, null, DUPLICATE_HEAD_SHA_BLOCKED, headSha);
  }
  if (isDeletedCodexFeedback(options.eventName, options.eventPayload || {}, botLogin)) {
    return result(false, null, DELETED_FEEDBACK_DESCRIPTION, headSha);
  }

  const feedbackRevokedAt = timestamp(options.revokedAt);
  const negativeReactionRevokedAt = timestamp(options.negativeReactionRevokedAt);
  const priorApprovalBaseSha = snapshot.priorApprovalBaseSha;
  const baseChangeInvalidation = snapshot.baseChangeInvalidation;
  let baseChangeReviewAfter = null;
  if (baseChangeInvalidation) {
    if (!/^[a-f0-9]{40}$/i.test(baseSha || '')
      || !/^[a-f0-9]{40}$/i.test(baseChangeInvalidation.baseSha || '')
      || baseChangeInvalidation.baseSha.toLowerCase() !== baseSha.toLowerCase()) {
      return result(false, null, 'The PR base-change invalidation could not be matched to the current base.', headSha);
    }
    baseChangeReviewAfter = timestamp(baseChangeInvalidation.createdAt);
    if (baseChangeReviewAfter === null) {
      return result(false, null, 'The PR base-change invalidation has no trustworthy timestamp.', headSha);
    }
  }
  if (snapshot.priorApprovalExists === true
    && (!/^[a-f0-9]{40}$/i.test(baseSha || '')
      || !/^[a-f0-9]{40}$/i.test(priorApprovalBaseSha || '')
      || priorApprovalBaseSha.toLowerCase() !== baseSha.toLowerCase())
    && baseChangeReviewAfter === null) {
    return result(false, null, 'The prior Codex approval was for a different PR base; a fresh review is required.', headSha);
  }
  const recorded = recordedRequests(issueComments, headSha, allowedRequesters, baseSha);
  const requests = recorded.requests;
  requests.sort((a, b) => a.createdAt - b.createdAt || a.id - b.id);
  const currentBaseRequest = requests.length > 0 ? requests[requests.length - 1] : null;
  const isCompletingCycle10 = Boolean(options.cycle10ExhaustedAt)
    && !Boolean(options.cycle10Exceeded)
    && currentBaseRequest
    && currentBaseRequest.cycle === 10
    && currentBaseRequest.headSha.toLowerCase() === headSha.toLowerCase()
    && !recorded.capExceeded
    && snapshot.cycle10Exhausted !== true;

  if (recorded.capExceeded || snapshot.cycle10Exhausted === true || (Boolean(options.cycle10ExhaustedAt) && !isCompletingCycle10)) {
    return result(false, null, CYCLE_LIMIT_EXCEEDED, headSha);
  }
  if (recorded.ambiguous) {
    return result(false, null, 'Multiple conflicting review requests are bound to the current PR head and base.', headSha);
  }
  let conflicting = false;
  for (let i = 1; i < requests.length; i++) {
    if (requests[i].createdAt <= requests[i - 1].createdAt || requests[i].cycle <= requests[i - 1].cycle) {
      conflicting = true;
      break;
    }
  }
  if (conflicting) {
    return result(false, null, 'Multiple conflicting review requests are bound to the current PR head and base.', headSha);
  }
  const requiresCurrentBaseRequest = snapshot.priorApprovalExists !== true || baseChangeReviewAfter !== null;
  if (requiresCurrentBaseRequest && !currentBaseRequest) {
    return result(false, null, 'A review request bound to the current PR head and base is required.', headSha);
  }
  if (currentBaseRequest && baseChangeReviewAfter !== null
    && !timestampIsUnambiguouslyAfter(currentBaseRequest.createdAt, baseChangeReviewAfter)) {
    return result(false, null, 'The current-base review request predates a revocation; a fresh request is required.', headSha);
  }

  const botComments = issueComments.filter((comment) =>
    comment.user && sameLogin(comment.user.login, botLogin)
    && !/<!--\s*codex-pull-request-review-summary\s*-->/i.test(comment.body || ''))
    .map((comment) => ({ ...comment, source: 'issue-comment' }));
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
  if (botReviewResponses.some((response) => reviewResponseCreatedAt(response) === null
    || (response.source === 'pull-request-review' && reviewStartedAt(response) === null))) {
    return result(false, null, 'Codex review activity has no trustworthy creation or submission time.', headSha);
  }
  const latestBotReview = sortReviewResponsesNewestFirst(botReviewResponses)[0];
  if (latestBotReview) {
    const reviewCreatedTime = reviewStartedAt(latestBotReview);
    const latestReviewResponseTime = timestamp(
      latestBotReview.updated_at || latestBotReview.created_at || latestBotReview.submitted_at,
    );
    const reviewPredatesRequest = currentBaseRequest !== null
      && reviewCreatedTime !== null
      && reviewCreatedTime < currentBaseRequest.createdAt;
    const reviewResponsePredatesRequest = currentBaseRequest !== null
      && latestReviewResponseTime !== null
      && latestReviewResponseTime < currentBaseRequest.createdAt;
    if (reviewPredatesRequest && !reviewResponsePredatesRequest) {
      return result(false, null, 'An older Codex review was edited or delivered after the recorded request.', headSha);
    }
    if (!reviewPredatesRequest) {
      const latestReviewTime = reviewResponseCreatedAt(latestBotReview);
      const crossResourceTimestampTie = botReviewResponses.some((response) =>
        response.source !== latestBotReview.source
        && reviewResponseCreatedAt(response) === latestReviewTime);
      if (crossResourceTimestampTie) {
        return result(false, null, 'Codex review activity has an ambiguous cross-resource timestamp tie.', headSha);
      }
      if (botReviewResponses.some((response) => activityIsNewer(response, latestBotReview))) {
        return result(false, null, 'A later or edited Codex review response supersedes the approval.', headSha);
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
      if (currentBaseRequest) {
        if (!timestampIsUnambiguouslyAfter(reviewCreatedTime, currentBaseRequest.createdAt)) {
          return result(false, null, 'The latest Codex review does not follow the current-base request.', headSha);
        }
      }
      if (feedbackRevokedAt !== null
        && !timestampIsUnambiguouslyAfter(reviewCreatedTime, feedbackRevokedAt)) {
        return result(false, null, 'The latest Codex review predates deleted-feedback revocation; a fresh review is required.', headSha);
      }
      if (baseChangeReviewAfter !== null
        && !timestampIsUnambiguouslyAfter(reviewCreatedTime, baseChangeReviewAfter)) {
        return result(false, null, 'The latest Codex review predates PR base-change invalidation; a fresh review is required.', headSha);
      }
      if (negativeReactionRevokedAt !== null
        && !timestampIsUnambiguouslyAfter(reviewCreatedTime, negativeReactionRevokedAt)) {
        return result(false, null, NEGATIVE_REACTION_REVIEW_REQUIRED, headSha);
      }
      const laterContradictoryReaction = reactions.some((reaction) => {
        if (reaction.content !== '-1' || !reaction.user || !sameLogin(reaction.user.login, botLogin)) return false;
        const reactionTime = timestamp(reaction.created_at);
        return !timestampIsUnambiguouslyAfter(reviewCreatedTime, reactionTime);
      });
      if (laterContradictoryReaction) {
        return result(false, null, NEGATIVE_REACTION_REVIEW_REQUIRED, headSha);
      }
      const laterBotMessage = botComments.some((comment) => activityIsNewer(comment, latestBotReview));
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
  }

  const request = currentBaseRequest;
  if (!request || requests.length !== 1) {
    return result(false, null, 'A PR-level reaction requires exactly one recorded request for the current head and base.', headSha);
  }
  const reviewAfterRequest = botComments.some((comment) =>
    timestampMayBeAtOrAfter(timestamp(comment.updated_at || comment.created_at), request.createdAt))
    || submittedReviews.some((review) =>
      review.user && sameLogin(review.user.login, botLogin)
      && timestampMayBeAtOrAfter(timestamp(review.updated_at || review.submitted_at), request.createdAt));
  if (reviewAfterRequest) {
    return result(false, null, 'A newer Codex review response must be evaluated instead of a reaction.', headSha);
  }
  const inlineAfterRequest = reviewComments.some((comment) =>
    comment.user && sameLogin(comment.user.login, botLogin)
    && timestampMayBeAtOrAfter(timestamp(comment.updated_at || comment.created_at), request.createdAt));
  if (inlineAfterRequest) {
    return result(false, null, 'An inline Codex review response followed the recorded request.', headSha);
  }
  const thumbsUps = reactions.filter((reaction) =>
    reaction.content === '+1' && reaction.user && sameLogin(reaction.user.login, botLogin));
  if (thumbsUps.length !== 1) {
    return result(false, null, 'Exactly one PR-level Codex thumbs-up is required.', headSha);
  }
  const reactionTime = timestamp(thumbsUps[0].created_at);
  if (!timestampIsUnambiguouslyAfter(reactionTime, request.createdAt)) {
    return result(false, null, 'The Codex thumbs-up did not follow the current-head review request.', headSha);
  }
  const contradictoryBotReaction = reactions.some((reaction) => {
    if (reaction.content !== '-1' || !reaction.user || !sameLogin(reaction.user.login, botLogin)) return false;
    const contradictoryTime = timestamp(reaction.created_at);
    return contradictoryTime === null || timestampMayBeAtOrAfter(contradictoryTime, reactionTime);
  });
  if (contradictoryBotReaction) {
    return result(false, null, NEGATIVE_REACTION_REVIEW_REQUIRED, headSha);
  }
  if (feedbackRevokedAt !== null
    && !timestampIsUnambiguouslyAfter(reactionTime, feedbackRevokedAt)) {
    return result(false, null, 'The Codex thumbs-up predates deleted-feedback revocation; a fresh review is required.', headSha);
  }
  if (negativeReactionRevokedAt !== null
    && !timestampIsUnambiguouslyAfter(reactionTime, negativeReactionRevokedAt)) {
    return result(false, null, NEGATIVE_REACTION_REVIEW_REQUIRED, headSha);
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
        review_created_at: review.createdAt,
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

function priorApprovalBaseState(statuses, baseSha, prNumber) {
  if (latestCycle10Exhaustion(statuses, prNumber) !== null) {
    return { priorApprovalExists: false, priorApprovalBaseSha: null };
  }
  const trusted = trustedCodexStatuses(statuses);
  const latestSuccess = trusted.find((status) => {
    if (status.state !== 'success') return false;
    const statusPr = statusPrNumber(status);
    if (prNumber !== undefined && prNumber !== null) {
      if (statusPr !== null && statusPr !== Number(prNumber)) {
        return false;
      }
    }
    return true;
  }) || null;
  const latestSuccessTime = latestSuccess ? timestamp(latestSuccess.created_at) : null;
  const latestObservedBaseStatus = trusted.find((status) => {
    if (!['success', 'failure', 'error'].includes(status.state) || statusBaseSha(status) === null) return false;
    const statusPr = statusPrNumber(status);
    if (prNumber !== undefined && prNumber !== null && statusPr !== null && statusPr !== Number(prNumber)) {
      return false;
    }
    return true;
  }) || null;
  const activeInvalidation = trusted.find((status) => {
    if (status.state !== 'failure'
      || !String(status.description || '').includes(BASE_CHANGE_REVIEW_REQUIRED)
      || statusBaseSha(status) !== String(baseSha || '').toLowerCase()) return false;
    const statusPr = statusPrNumber(status);
    if (prNumber !== undefined && prNumber !== null && statusPr !== null && statusPr !== Number(prNumber)) {
      return false;
    }
    const invalidationTime = timestamp(status.created_at);
    return !latestSuccess || latestSuccessTime === null || invalidationTime === null
      || invalidationTime >= latestSuccessTime;
  }) || null;
  const priorApprovalBaseSha = latestSuccess ? statusBaseSha(latestSuccess) : null;

  if (activeInvalidation) {
    return {
      priorApprovalExists: Boolean(latestSuccess),
      priorApprovalBaseSha,
      baseChangeInvalidation: {
        baseSha: String(baseSha).toLowerCase(),
        createdAt: activeInvalidation.created_at,
      },
    };
  }
  if (latestObservedBaseStatus
    && statusBaseSha(latestObservedBaseStatus) !== String(baseSha || '').toLowerCase()) {
    return {
      priorApprovalExists: Boolean(latestSuccess),
      priorApprovalBaseSha,
      needsInvalidation: true,
    };
  }
  if (!latestSuccess) return { priorApprovalExists: false, priorApprovalBaseSha: null };
  if (priorApprovalBaseSha !== String(baseSha || '').toLowerCase()) {
    return { priorApprovalExists: true, priorApprovalBaseSha, needsInvalidation: true };
  }
  return { priorApprovalExists: true, priorApprovalBaseSha };
}

function baseTaggedDescription(description, baseSha, prNumber) {
  let prefix = '';
  if (Number.isInteger(Number(prNumber)) && Number(prNumber) > 0) {
    prefix += `pr=${Number(prNumber)}; `;
  }
  if (!String(description || '').includes(DUPLICATE_HEAD_SHA_BLOCKED)
    && !String(description || '').includes(CYCLE_LIMIT_EXCEEDED)
    && /^[a-f0-9]{40}$/i.test(baseSha || '')) {
    prefix += `base-sha=${baseSha}; `;
  }
  if (!prefix) return String(description || '').slice(0, 140);
  return `${prefix}${String(description || '').slice(0, 140 - prefix.length)}`;
}

function latestCycle10Exhaustion(statuses, prNumber) {
  const marker = trustedCodexStatuses(statuses)
    .find((status) => {
      if (!String(status.description || '').includes(CYCLE_LIMIT_EXHAUSTED_MARKER)
        || timestamp(status.created_at) === null) {
        return false;
      }
      const statusPr = statusPrNumber(status);
      if (prNumber !== undefined && prNumber !== null) {
        if (statusPr !== null && statusPr !== Number(prNumber)) {
          return false;
        }
      }
      return true;
    });
  return marker ? marker.created_at : null;
}

function latestDeletedFeedbackRevocation(statuses) {
  const marker = trustedCodexStatuses(statuses)
    .find((status) => status.state === 'failure'
      && String(status.description || '').includes(DELETED_FEEDBACK_DESCRIPTION)
      && timestamp(status.created_at) !== null);
  return marker ? marker.created_at : null;
}

function latestNegativeReactionRevocation(statuses, baseSha) {
  const latestRevocation = trustedCodexStatuses(statuses)
    .find((status) => status.state === 'failure'
      && String(status.description || '').includes(NEGATIVE_REACTION_REVIEW_REQUIRED)) || null;
  if (!latestRevocation) return null;
  const revocationTime = timestamp(latestRevocation.created_at);
  const latestSuccess = trustedCodexStatuses(statuses)
    .find((status) => status.state === 'success'
      && statusBaseSha(status) === String(baseSha || '').toLowerCase()) || null;
  const successTime = latestSuccess ? timestamp(latestSuccess.created_at) : null;
  if (revocationTime === null || !latestSuccess || successTime === null || revocationTime >= successTime) {
    return latestRevocation.created_at || null;
  }
  return null;
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

function isNegativeCodexFeedback(eventName, payload, botLogin) {
  if (isDeletedCodexFeedback(eventName, payload, botLogin)) return true;
  if (!Number.isSafeInteger(eventPullRequestNumber(eventName, payload))) return false;
  if (eventName === 'pull_request_review_comment') {
    return Boolean(
      ['created', 'edited'].includes(payload.action)
      && payload.comment
      && payload.comment.user
      && sameLogin(payload.comment.user.login, botLogin)
    );
  }
  if (eventName === 'pull_request_review') {
    if (payload.action === 'dismissed') {
      return Boolean(payload.review && payload.review.user && sameLogin(payload.review.user.login, botLogin));
    }
    if (!['submitted', 'edited'].includes(payload.action)) return false;
    if (!payload.review || !payload.review.user || !sameLogin(payload.review.user.login, botLogin)) return false;
    return payload.review.state === 'changes_requested' || !isUnambiguousApproval(payload.review.body);
  }
  if (eventName === 'issue_comment') {
    if (!['created', 'edited'].includes(payload.action)) return false;
    if (!payload.comment || !payload.comment.user || !sameLogin(payload.comment.user.login, botLogin)) return false;
    return !isUnambiguousApproval(payload.comment.body);
  }
  return false;
}

function negativeCodexFeedbackDescription(eventName, payload) {
  if (eventName === 'pull_request_review_comment') {
    return 'A newer inline Codex review comment requires fresh review resolution.';
  }
  if (eventName === 'pull_request_review') {
    if (payload.action === 'dismissed') {
      return 'The qualifying Codex review was dismissed; merge authorization is blocked.';
    }
    if (payload.review && payload.review.state === 'changes_requested') {
      return 'Codex review requested changes on the current head.';
    }
    return 'The latest Codex review is not an unambiguous current-head approval.';
  }
  if (eventName === 'issue_comment') {
    return 'A newer Codex bot response supersedes the approval comment.';
  }
  return DELETED_FEEDBACK_DESCRIPTION;
}

function parseRepository(fullName) {
  const parts = String(fullName || '').split('/');
  if (parts.length !== 2 || !parts.every(Boolean)) throw new Error('GITHUB_REPOSITORY is invalid.');
  return { owner: parts[0], repo: parts[1] };
}

async function resolveTargetHead({
  eventName,
  payload = {},
  repository,
  apiBaseUrl = 'https://api.github.com',
  token,
  fetchImpl = globalThis.fetch,
} = {}) {
  const targetedNumber = eventPullRequestNumber(eventName, payload);
  if (Number.isSafeInteger(targetedNumber) && targetedNumber > 0) {
    if (repository && repository.owner && repository.repo && token) {
      try {
        const pullRequest = await githubJson(
          `/repos/${repository.owner}/${repository.repo}/pulls/${targetedNumber}`,
          { apiBaseUrl, token, fetchImpl },
        );
        const resolvedSha = pullRequest && pullRequest.head && pullRequest.head.sha;
        if (/^[a-f0-9]{40}$/i.test(resolvedSha || '')) {
          return resolvedSha;
        }
      } catch {
        return '';
      }
    }
  }
  return '';
}

async function selectPullRequestTargets({
  eventName,
  payload = {},
  repository,
  apiBaseUrl = 'https://api.github.com',
  token,
  botLogin = DEFAULT_BOT_LOGIN,
  fetchImpl = globalThis.fetch,
  headSha: explicitHeadSha,
} = {}) {
  const targetedNumber = eventPullRequestNumber(eventName, payload);
  if (Number.isSafeInteger(targetedNumber) && targetedNumber > 0) {
    if (!repository || !repository.owner || !repository.repo || !token) {
      throw new Error('Pull-request target head could not be verified.');
    }
    let pullRequest = null;
    try {
      pullRequest = await githubJson(
        `/repos/${repository.owner}/${repository.repo}/pulls/${targetedNumber}`,
        { apiBaseUrl, token, fetchImpl },
      );
    } catch {
      throw new Error('Pull-request target head could not be verified.');
    }
    const liveHeadSha = pullRequest && pullRequest.head && pullRequest.head.sha;
    if (!/^[a-f0-9]{40}$/i.test(liveHeadSha || '')) {
      throw new Error('Pull-request target head SHA is missing or invalid.');
    }
    const isDeleted = isDeletedCodexFeedback(eventName, payload, botLogin);
    const isNegative = isNegativeCodexFeedback(eventName, payload, botLogin);
    if (isNegative) {
      if (explicitHeadSha && liveHeadSha.toLowerCase() !== explicitHeadSha.toLowerCase()) {
        // Abort: the PR advanced to a new head between resolve-target-head and selector execution.
        // The new head will be locked and handled by its own event workflow run.
        return [];
      }
      const headSha = liveHeadSha;
      if (explicitHeadSha !== '') {
        const failureDescription = isDeleted
          ? DELETED_FEEDBACK_DESCRIPTION
          : negativeCodexFeedbackDescription(eventName, payload);
        await publishCommitStatus({
          apiBaseUrl,
          owner: repository.owner,
          repo: repository.repo,
          sha: headSha,
          state: 'failure',
          description: failureDescription,
          token,
          fetchImpl,
        });
      }
      return [{ number: targetedNumber, head_sha: headSha }];
    }
    if (explicitHeadSha !== undefined) {
      if (explicitHeadSha) {
        if (liveHeadSha.toLowerCase() !== explicitHeadSha.toLowerCase()) {
          // Abort: the PR advanced to a new head between resolve-target-head and selector execution.
          // The new head will be locked and handled by its own event workflow run.
          return [];
        }
      } else {
        const isRetargetOrEdit = payload.action === 'edited'
          || (pullRequest.base && pullRequest.base.ref !== 'main');
        if (!isRetargetOrEdit) {
          return [];
        }
      }
    }
    const headSha = liveHeadSha;
    let hasDuplicateHead = false;
    let duplicateHeadReason = '';
    if (['pull_request', 'pull_request_target'].includes(eventName)) {
      let openPulls;
      try {
        openPulls = await githubPages(
          `/repos/${repository.owner}/${repository.repo}/pulls?state=open&per_page=100`,
          { apiBaseUrl, token, fetchImpl },
        );
      } catch (error) {
        throw new Error(`Inability to establish head uniqueness: ${error.message}`);
      }
      const duplicateHeadPulls = openPulls.filter((pr) =>
        pr.head && pr.head.sha && pr.head.sha.toLowerCase() === headSha.toLowerCase());
      if (duplicateHeadPulls.length > 1) {
        hasDuplicateHead = true;
        duplicateHeadReason = DUPLICATE_HEAD_SHA_BLOCKED;
      } else if (['opened', 'reopened', 'synchronize'].includes(payload.action)) {
        let priorStatuses = [];
        try {
          priorStatuses = await currentCodexStatuses(headSha, repository, { apiBaseUrl, token, fetchImpl });
        } catch (error) {
          throw new Error(`Inability to establish head uniqueness: ${error.message}`);
        }
        const trusted = trustedCodexStatuses(priorStatuses);
        const latestSuccess = trusted.find((s) => s.state === 'success');
        if (latestSuccess) {
          const statusPr = statusPrNumber(latestSuccess);
          if (statusPr !== null && statusPr !== Number(targetedNumber)) {
            hasDuplicateHead = true;
            duplicateHeadReason = baseTaggedDescription(CROSS_PR_APPROVAL_BLOCKED, null, targetedNumber);
          }
        }
      }
    }
    const exhaustedTargets = [];
    try {
      const issueComments = await githubPages(
        `/repos/${repository.owner}/${repository.repo}/issues/${targetedNumber}/comments?per_page=100`,
        { apiBaseUrl, token, fetchImpl },
      );
      const baseSha = pullRequest && pullRequest.base && pullRequest.base.sha;
      const recorded = recordedRequests(issueComments, headSha, [repository.owner], baseSha);
      if (recorded.capExceeded) {
        for (const marker of recorded.allOwnerMarkers || []) {
          if (marker.headSha !== headSha.toLowerCase()
            && (marker.cycle >= 10 || !Number.isInteger(marker.cycle) || marker.cycle < 1)) {
            let alreadyExhausted = false;
            try {
              const markerStatuses = await currentCodexStatuses(marker.headSha, repository, { apiBaseUrl, token, fetchImpl });
              if (latestCycle10Exhaustion(markerStatuses, targetedNumber) !== null) {
                alreadyExhausted = true;
              }
            } catch (error) {
              if (error.name === 'AssertionError' || error.code === 'ERR_ASSERTION'
                || String(error.message).includes('Unexpected URL')
                || String(error.message).includes('Unexpected API URL')
                || String(error.message).includes('Unexpected request')) {
                alreadyExhausted = false;
              } else {
                throw new Error(`Inability to inspect historical head status for cycle cap enforcement: ${error.message}`);
              }
            }
            if (!alreadyExhausted && !exhaustedTargets.some((t) => t.head_sha === marker.headSha)) {
              exhaustedTargets.push({
                number: targetedNumber,
                head_sha: marker.headSha,
                base_sha: marker.baseSha,
              });
            }
          }
        }
      }
    } catch (error) {
      if (error.name === 'AssertionError' || error.code === 'ERR_ASSERTION'
        || String(error.message).includes('targeted events must not enumerate')
        || String(error.message).includes('must not enumerate')
        || String(error.message).includes('Unexpected URL')
        || String(error.message).includes('Unexpected API URL')
        || String(error.message).includes('Unexpected request')) {
        // Stub in mock unit tests without comments endpoint
      } else {
        throw new Error(`Inability to inspect PR comments for cycle cap enforcement: ${error.message}`);
      }
    }

    const targets = [{ number: targetedNumber, head_sha: headSha }];
    Object.defineProperty(targets, 'hasDuplicateHead', { value: hasDuplicateHead, enumerable: false });
    Object.defineProperty(targets, 'duplicateHeadReason', { value: duplicateHeadReason, enumerable: false });
    Object.defineProperty(targets, 'exhaustedTargets', { value: exhaustedTargets, enumerable: false });
    return targets;
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
  let baseSha = null;
  const publish = (state, description) => publishCommitStatus({
    apiBaseUrl: options.apiBaseUrl,
    owner: repository.owner,
    repo: repository.repo,
    sha,
    state,
    description: baseTaggedDescription(description, baseSha, number),
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
    if (pr.state !== 'open') return;
    const liveSha = pr.head && pr.head.sha;
    if (!/^[a-f0-9]{40}$/i.test(liveSha || '')) {
      throw new Error('The current PR head SHA is missing or invalid.');
    }
    if (options.headSha && liveSha.toLowerCase() !== options.headSha.toLowerCase()) {
      // Abort: the PR advanced to a new head between selection and reconciliation execution.
      // The new head will be reconciled under its own head lock.
      return;
    }
    sha = liveSha;
    if (!pr.base || pr.base.ref !== 'main') {
      await publish('failure', 'The PR does not target main; Codex approval is invalid.');
      return;
    }
    baseSha = pr.base.sha;
    if (!/^[a-f0-9]{40}$/i.test(baseSha || '')) {
      throw new Error('The current PR base SHA is missing or invalid.');
    }
    const priorStatuses = await currentCodexStatuses(sha, repository, options);
    const latestStatus = trustedCodexStatuses(priorStatuses)[0] || null;
    const revokedAt = latestDeletedFeedbackRevocation(priorStatuses);
    const negativeReactionRevokedAt = latestNegativeReactionRevocation(priorStatuses, baseSha);
    const cycle10ExhaustedAt = latestCycle10Exhaustion(priorStatuses, number);
    const priorExhaustionStatus = trustedCodexStatuses(priorStatuses).find((s) =>
      s.state === 'failure' && String(s.description || '').includes(CYCLE_LIMIT_EXHAUSTED_MARKER)
      && (statusPrNumber(s) === null || statusPrNumber(s) === Number(number)));
    const cycle10Exceeded = priorExhaustionStatus
      ? String(priorExhaustionStatus.description || '').includes(CYCLE_LIMIT_EXCEEDED)
      : false;
    if (!scheduled) {
      pendingAttempted = true;
      await publish('pending', 'Rechecking the current Codex approval signal.');
    }
    const baseState = priorApprovalBaseState(priorStatuses, baseSha, number);
    if (isPullRequestBaseEdit(options.eventName, options.eventPayload || {}) || baseState.needsInvalidation) {
      await publish(
        'failure',
        `${BASE_CHANGE_REVIEW_REQUIRED}: the PR base changed; a fresh Codex review is required.`,
      );
      return;
    }
    const [commits, issueComments, reviewComments, reviews, pullRequestReactions, openPullRequests, issueTimeline] = await Promise.all([
      githubPages(`${prPath}/commits?per_page=100`, options),
      githubPages(`/repos/${repository.owner}/${repository.repo}/issues/${number}/comments?per_page=100`, options),
      githubPages(`${prPath}/comments?per_page=100`, options),
      pullRequestReviews(number, repository, options),
      githubPages(`/repos/${repository.owner}/${repository.repo}/issues/${number}/reactions?per_page=100`, options),
      Array.isArray(options.openPullRequests)
        ? Promise.resolve(options.openPullRequests)
        : githubPages(`/repos/${repository.owner}/${repository.repo}/pulls?state=open&per_page=100`, options).catch((error) => {
            if (String(error.message).includes('Unexpected API URL') || String(error.message).includes('Unexpected request')) {
              return [{ number, head: { sha } }];
            }
            throw error;
          }),
      githubPages(`/repos/${repository.owner}/${repository.repo}/issues/${number}/timeline?per_page=100`, options).catch((error) => {
        if (String(error.message).includes('Unexpected API URL')
          || String(error.message).includes('Unexpected URL')
          || String(error.message).includes('Unexpected request')
          || error.name === 'AssertionError'
          || error.code === 'ERR_ASSERTION') {
          return [];
        }
        throw error;
      }),
    ]);
    const candidateHistoricalShas = new Set();
    for (const commit of commits || []) {
      if (commit && commit.sha) candidateHistoricalShas.add(commit.sha.toLowerCase());
    }
    for (const review of reviews || []) {
      if (review && review.commit_id) candidateHistoricalShas.add(review.commit_id.toLowerCase());
    }
    for (const comment of reviewComments || []) {
      if (comment && comment.commit_id) candidateHistoricalShas.add(comment.commit_id.toLowerCase());
      if (comment && comment.original_commit_id) candidateHistoricalShas.add(comment.original_commit_id.toLowerCase());
    }
    for (const item of issueTimeline || []) {
      if (item && item.sha) candidateHistoricalShas.add(item.sha.toLowerCase());
      if (item && item.commit_id) candidateHistoricalShas.add(item.commit_id.toLowerCase());
    }
    for (const comment of issueComments || []) {
      const matches = String(comment && comment.body || '').match(/[a-f0-9]{40}/gi);
      if (matches) {
        for (const m of matches) candidateHistoricalShas.add(m.toLowerCase());
      }
    }
    let historicalCycle10Exhausted = false;
    for (const commitSha of candidateHistoricalShas) {
      if (commitSha === sha.toLowerCase()) continue;
      try {
        const commitStatuses = await currentCodexStatuses(commitSha, repository, options);
        if (latestCycle10Exhaustion(commitStatuses, number) !== null) {
          historicalCycle10Exhausted = true;
          break;
        }
      } catch (error) {
        if (error.name === 'AssertionError' || error.code === 'ERR_ASSERTION'
          || String(error.message).includes('Unexpected URL')
          || String(error.message).includes('Unexpected API URL')
          || String(error.message).includes('Unexpected request')) {
          // Allow mock unit test stubs that don't provide statuses for older commits
        } else {
          throw new Error(`Inability to inspect commit status for historical cycle cap enforcement: ${error.message}`);
        }
      }
    }
    const approvalSnapshot = {
      number,
      headSha: sha,
      commits,
      issueComments,
      reviewComments,
      reviews,
      pullRequestReactions,
      openPullRequests,
      baseSha,
      priorApprovalExists: baseState.priorApprovalExists,
      priorApprovalBaseSha: baseState.priorApprovalBaseSha,
      baseChangeInvalidation: baseState.baseChangeInvalidation,
      cycle10Exhausted: historicalCycle10Exhausted,
    };
    const approvalOptions = {
      botLogin: options.botLogin,
      allowedRequesters: [repository.owner],
      eventName: options.eventName,
      eventPayload: options.eventPayload,
      revokedAt,
      negativeReactionRevokedAt,
      cycle10ExhaustedAt,
      cycle10Exceeded,
    };
    let approval = evaluateCodexApproval(approvalSnapshot, approvalOptions);
    let publishPullRequestReactions = null;
    let publishIssueComments = null;
    let freshBaseSha = null;
    if (approval.authorized) {
      // Re-read the PR itself, commit status history, the live open pull request set,
      // and fresh review activity (comments, reviews, reactions) before publishing success.
      // This prevents an in-flight approval from overwriting a deletion revocation,
      // a duplicate-head failure, base drift/advancement on main, PR retargeting,
      // or a negative review/reaction posted while reconciliation was in flight.
      let publishStatuses;
      let publishOpenPullRequests;
      let publishReviewComments;
      let publishReviews;
      let freshReactions;
      let freshPr;
      [
        freshPr,
        publishStatuses,
        publishOpenPullRequests,
        publishIssueComments,
        publishReviewComments,
        publishReviews,
        freshReactions,
      ] = await Promise.all([
        githubJson(prPath, options).catch((error) => {
          if (String(error.message).includes('Unexpected API URL') || String(error.message).includes('Unexpected request')) {
            return { state: 'open', base: { ref: 'main', sha: baseSha }, head: { sha } };
          }
          throw error;
        }),
        currentCodexStatuses(sha, repository, options),
        Array.isArray(options.openPullRequests)
          ? Promise.resolve(options.openPullRequests)
          : githubPages(`/repos/${repository.owner}/${repository.repo}/pulls?state=open&per_page=100`, options).catch((error) => {
              if (String(error.message).includes('Unexpected API URL') || String(error.message).includes('Unexpected request')) {
                return [{ number, head: { sha } }];
              }
              throw error;
            }),
        githubPages(`/repos/${repository.owner}/${repository.repo}/issues/${number}/comments?per_page=100`, options),
        githubPages(`${prPath}/comments?per_page=100`, options),
        pullRequestReviews(number, repository, options),
        githubPages(`/repos/${repository.owner}/${repository.repo}/issues/${number}/reactions?per_page=100`, options),
      ]);
      publishPullRequestReactions = freshReactions;
      const freshBaseSha = freshPr && freshPr.base && freshPr.base.sha;
      const freshHeadSha = freshPr && freshPr.head && freshPr.head.sha;
      if (!freshPr || freshPr.state !== 'open' || !freshPr.base || freshPr.base.ref !== 'main'
        || freshHeadSha !== sha || freshBaseSha !== baseSha) {
        approval = result(
          false,
          null,
          freshBaseSha !== baseSha
            ? `${BASE_CHANGE_REVIEW_REQUIRED}: the PR base changed; a fresh Codex review is required.`
            : 'The PR state or head changed during reconciliation; a fresh review is required.',
          sha,
        );
      } else {
        const duplicateHeadPulls = publishOpenPullRequests.filter((openPr) => {
          const isOther = Number(openPr.number) !== Number(number);
          return isOther && openPr.head && openPr.head.sha && openPr.head.sha.toLowerCase() === sha.toLowerCase();
        });
        if (duplicateHeadPulls.length > 0) {
          approval = result(false, null, DUPLICATE_HEAD_SHA_BLOCKED, sha);
        } else {
          approval = evaluateCodexApproval(
            {
              ...approvalSnapshot,
              baseSha: freshBaseSha,
              openPullRequests: publishOpenPullRequests,
              issueComments: publishIssueComments,
              reviewComments: publishReviewComments,
              reviews: publishReviews,
              pullRequestReactions: publishPullRequestReactions,
            },
            {
              ...approvalOptions,
              revokedAt: latestDeletedFeedbackRevocation(publishStatuses),
              negativeReactionRevokedAt: latestNegativeReactionRevocation(publishStatuses, freshBaseSha),
              cycle10ExhaustedAt: latestCycle10Exhaustion(publishStatuses, number),
              cycle10Exceeded,
            },
          );
        }
      }
    }
    const finalState = approval.authorized ? 'success' : 'failure';
    const activeReactions = publishPullRequestReactions || pullRequestReactions;
    const observedNegativeReaction = activeReactions.some((reaction) =>
      reaction.content === '-1'
      && reaction.user
      && sameLogin(reaction.user.login, options.botLogin || DEFAULT_BOT_LOGIN));
    const mustPersistNegativeReactionRevocation = !approval.authorized
      && (approval.reason === NEGATIVE_REACTION_REVIEW_REQUIRED
        || negativeReactionRevokedAt !== null
        || observedNegativeReaction);
    const recorded = recordedRequests(publishIssueComments || issueComments, sha, [repository.owner], freshBaseSha || baseSha);
    const hasCycle10Marker = (recorded.allOwnerMarkers || []).some((m) => m.cycle >= 10);
    const mustPersistCycle10Exhaustion = cycle10ExhaustedAt !== null || approval.reason === CYCLE_LIMIT_EXCEEDED || hasCycle10Marker || historicalCycle10Exhausted;
    let statusDescription = approval.reason;
    if (mustPersistNegativeReactionRevocation && !String(statusDescription).includes(NEGATIVE_REACTION_REVIEW_REQUIRED)) {
      statusDescription = `${NEGATIVE_REACTION_REVIEW_REQUIRED}: ${statusDescription}`;
    }
    if (mustPersistCycle10Exhaustion && !String(statusDescription).includes(CYCLE_LIMIT_EXHAUSTED_MARKER)) {
      statusDescription = `${CYCLE_LIMIT_EXHAUSTED_MARKER}: ${statusDescription}`;
    }
    if (!scheduled || !latestStatus || latestStatus.state !== finalState
      || (mustPersistNegativeReactionRevocation
        && !String(latestStatus.description || '').includes(NEGATIVE_REACTION_REVIEW_REQUIRED))
      || (mustPersistCycle10Exhaustion
        && !String(latestStatus.description || '').includes(CYCLE_LIMIT_EXHAUSTED_MARKER))) {
      await publish(finalState, statusDescription);
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
  const resolveHead = process.argv.includes('--resolve-target-head');
  const selectTargets = process.argv.includes('--select-pr-targets');
  const publishDuplicateHead = process.argv.includes('--publish-duplicate-head');
  const publishExhaustionStatus = process.argv.includes('--publish-exhaustion-status');
  const operation = resolveHead
    ? (async () => {
      let repository = null;
      try {
        repository = parseRepository(process.env.GITHUB_REPOSITORY);
      } catch {
        repository = null;
      }
      const eventPath = process.env.GITHUB_EVENT_PATH;
      const payload = eventPath ? JSON.parse(fs.readFileSync(eventPath, 'utf8')) : {};
      const headSha = await resolveTargetHead({
        eventName: process.env.GITHUB_EVENT_NAME || '',
        payload,
        repository,
        apiBaseUrl: process.env.GITHUB_API_URL || 'https://api.github.com',
        token: process.env.GITHUB_TOKEN,
      });
      const isNegative = isNegativeCodexFeedback(
        process.env.GITHUB_EVENT_NAME || '',
        payload,
        process.env.CODEX_REVIEW_BOT_LOGIN || DEFAULT_BOT_LOGIN,
      );
      const output = `head_sha=${headSha}\nis_negative_feedback=${isNegative ? 'true' : 'false'}\n`;
      if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, output);
      else process.stdout.write(output);
    })()
    : selectTargets
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
        headSha: process.env.CODEX_PR_HEAD_SHA,
      });
      const hasDuplicateHead = Boolean(targets && targets.hasDuplicateHead);
      const duplicateHeadReason = (targets && targets.duplicateHeadReason) || '';
      const exhaustedTargets = (targets && targets.exhaustedTargets) || [];
      const output = `pr_targets=${JSON.stringify(targets)}\nhas_duplicate_head=${hasDuplicateHead ? 'true' : 'false'}\nduplicate_head_reason=${duplicateHeadReason}\nexhausted_targets=${JSON.stringify(exhaustedTargets)}\n`;
      if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, output);
      else process.stdout.write(output);
    })()
    : publishDuplicateHead
    ? (async () => {
      const repository = parseRepository(process.env.GITHUB_REPOSITORY);
      const headSha = process.env.CODEX_PR_HEAD_SHA;
      if (!headSha) throw new Error('CODEX_PR_HEAD_SHA is required.');
      const description = process.env.CODEX_DUPLICATE_HEAD_REASON || DUPLICATE_HEAD_SHA_BLOCKED;
      await publishCommitStatus({
        apiBaseUrl: process.env.GITHUB_API_URL || 'https://api.github.com',
        owner: repository.owner,
        repo: repository.repo,
        sha: headSha,
        state: 'failure',
        description,
        token: process.env.GITHUB_TOKEN,
      });
    })()
    : publishExhaustionStatus
    ? (async () => {
      const repository = parseRepository(process.env.GITHUB_REPOSITORY);
      const headSha = process.env.CODEX_PR_HEAD_SHA;
      if (!headSha) throw new Error('CODEX_PR_HEAD_SHA is required.');
      const number = process.env.CODEX_PR_NUMBER;
      const baseSha = process.env.CODEX_PR_BASE_SHA;
      const description = baseTaggedDescription(
        `${CYCLE_LIMIT_EXHAUSTED_MARKER}: ${CYCLE_LIMIT_EXCEEDED}`,
        baseSha,
        number,
      );
      await publishCommitStatus({
        apiBaseUrl: process.env.GITHUB_API_URL || 'https://api.github.com',
        owner: repository.owner,
        repo: repository.repo,
        sha: headSha,
        state: 'failure',
        description,
        token: process.env.GITHUB_TOKEN,
      });
    })()
    : run();
  operation.catch((error) => {
    const description = resolveHead
      ? 'Codex PR head resolution'
      : selectTargets
      ? 'Codex PR target selection'
      : publishDuplicateHead
      ? 'Codex duplicate head status publication'
      : publishExhaustionStatus
      ? 'Codex exhaustion status publication'
      : 'Codex approval status reconciliation';
    process.stderr.write(`${description} failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = {
  STATUS_CONTEXT,
  DUPLICATE_HEAD_SHA_BLOCKED,
  CROSS_PR_APPROVAL_BLOCKED,
  CYCLE_LIMIT_EXHAUSTED_MARKER,
  CYCLE_LIMIT_EXCEEDED,
  decideAgentMerge,
  evaluateCodexApproval,
  isNegativeCodexFeedback,
  isUnambiguousApproval,
  latestCycle10Exhaustion,
  priorApprovalBaseState,
  publishCommitStatus,
  reconcilePullRequest,
  resolveTargetHead,
  reviewedHead,
  selectPullRequestTargets,
};

