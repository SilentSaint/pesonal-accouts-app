const defaultTerms = '(alert OR statement OR debited OR credited OR transaction OR "spent" OR "bill" OR "card" OR "vpa" OR "upi" OR "inr" OR "rs")';

function toUnixSeconds(timestamp) {
  if (typeof timestamp === 'number' && Number.isFinite(timestamp)) {
    return Math.floor(timestamp);
  }

  const milliseconds = new Date(timestamp).getTime();
  return Number.isFinite(milliseconds) ? Math.floor(milliseconds / 1000) : null;
}

function buildGmailScanRequest(customQuery, options = {}, now = Date.now()) {
  const query = typeof customQuery === 'string' ? customQuery.trim() : '';
  const afterSeconds = toUnixSeconds(options.afterTimestamp);
  const beforeSeconds = toUnixSeconds(options.beforeTimestamp);
  const queryParts = [];

  if (afterSeconds !== null) {
    queryParts.push(`after:${afterSeconds}`);
  } else if (!query || (!query.includes('after:') && !query.includes('newer_than:'))) {
    queryParts.push(`after:${Math.floor((now - (30 * 24 * 60 * 60 * 1000)) / 1000)}`);
  }

  if (beforeSeconds !== null) {
    queryParts.push(`before:${beforeSeconds}`);
  }

  queryParts.push(query || defaultTerms);

  const requestedMaxResults = Number(options.maxResults);
  return {
    query: queryParts.join(' '),
    maxResults: Number.isFinite(requestedMaxResults)
      ? Math.min(Math.max(Math.floor(requestedMaxResults), 50), 500)
      : 500,
  };
}

module.exports = { buildGmailScanRequest };
