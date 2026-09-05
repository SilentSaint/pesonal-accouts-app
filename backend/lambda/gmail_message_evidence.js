const { TextDecoder } = require('node:util');

const MAX_EVIDENCE_CHARACTERS = 8000;
const MAX_ENCODED_PART_CHARACTERS = 65536;
const MAX_MIME_PARTS = 64;
const MAX_MIME_DEPTH = 16;

function htmlToText(html) {
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
  const chunks = [];
  let position = 0;
  while (position < html.length) {
    const opening = html.indexOf('<', position);
    if (opening === -1) {
      chunks.push(html.slice(position));
      break;
    }
    chunks.push(html.slice(position, opening));
    if (html.startsWith('<!--', opening)) {
      const closing = html.indexOf('-->', opening + 4);
      position = closing === -1 ? html.length : closing + 3;
      continue;
    }
    let end = opening + 1;
    let quote = '';
    for (; end < html.length; end++) {
      const character = html[end];
      if (quote) {
        if (character === quote) quote = '';
      } else if (character === '"' || character === "'") {
        quote = character;
      } else if (character === '>') {
        break;
      }
    }
    if (end === html.length) break;
    const tag = html.slice(opening + 1, end).match(/^\/?\s*([a-z][a-z0-9]*)/i)?.[1].toLowerCase();
    position = end + 1;
    if (['script', 'style', 'head'].includes(tag) && html[opening + 1] !== '/') {
      const closingTag = new RegExp(`</${tag}(?=[\\s>])`, 'ig');
      closingTag.lastIndex = position;
      const closing = closingTag.exec(html)?.index ?? -1;
      const closingEnd = closing === -1 ? -1 : html.indexOf('>', closing);
      position = closingEnd === -1 ? html.length : closingEnd + 1;
    } else if (['p', 'div', 'br', 'tr', 'td', 'th', 'li', 'table', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'].includes(tag)) {
      chunks.push(' ');
    }
  }
  return chunks.join('')
    .replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);/gi, (match, entity) => {
      if (!entity.startsWith('#')) return entities[entity.toLowerCase()];
      const code = /^#x/i.test(entity)
        ? parseInt(entity.slice(2), 16)
        : parseInt(entity.slice(1), 10);
      return code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff)
        ? String.fromCodePoint(code)
        : match;
    })
    .replace(/\s+/g, ' ')
    .trim();
}

function messageBody(part, budget, depth = 0) {
  const empty = { text: '', source: 'snippet', unsupported: false, truncated: false };
  if (budget.remaining === 0) {
    return { ...empty, truncated: true };
  }
  budget.remaining--;
  if (depth > MAX_MIME_DEPTH) return { ...empty, truncated: true };
  const disposition = part?.headers?.find(
    (header) => header.name.toLowerCase() === 'content-disposition',
  )?.value || '';
  if (!part || part.filename || /^attachment\b/i.test(disposition)) return empty;
  if (['text/plain', 'text/html'].includes(part.mimeType)) {
    const encoded = part.body?.data;
    if (!encoded) return { ...empty, unsupported: Boolean(part.body?.attachmentId) };
    const truncated = encoded.length > MAX_ENCODED_PART_CHARACTERS;
    const data = encoded.slice(0, MAX_ENCODED_PART_CHARACTERS);
    const contentType = part.headers?.find(
      (header) => header.name.toLowerCase() === 'content-type',
    )?.value || '';
    const charset = contentType.match(/charset\s*=\s*"?([^";\s]+)/i)?.[1]?.toLowerCase() || 'utf-8';
    if (!['utf-8', 'utf8', 'us-ascii'].includes(charset) ||
        !/^[a-z0-9_-]+={0,2}$/i.test(data) || data.replace(/=+$/, '').length % 4 === 1) {
      return { ...empty, unsupported: true, truncated };
    }
    let decoded;
    try {
      decoded = new TextDecoder('utf-8', { fatal: true })
        .decode(Buffer.from(data, 'base64url'), { stream: truncated }).trim();
    } catch (error) {
      if (error.code !== 'ERR_ENCODING_INVALID_ENCODED_DATA') throw error;
      return { ...empty, unsupported: true, truncated };
    }
    return {
      text: part.mimeType === 'text/html' ? htmlToText(decoded) : decoded,
      source: part.mimeType === 'text/html' ? 'html' : 'plain_text',
      unsupported: false,
      truncated,
    };
  }
  if (!part.mimeType?.startsWith('multipart/')) {
    return { ...empty, unsupported: Boolean(part.body?.data || part.body?.attachmentId) };
  }
  const children = [];
  for (const child of part.parts || []) {
    if (budget.remaining === 0) {
      children.push({ ...empty, truncated: true });
      break;
    }
    children.push(messageBody(child, budget, depth + 1));
  }
  if (part.mimeType === 'multipart/alternative') {
    return children.find((child) => child.text && child.source === 'plain_text')
      || children.find((child) => child.text)
      || {
        ...empty,
        unsupported: children.some((child) => child.unsupported),
        truncated: children.some((child) => child.truncated),
      };
  }
  return {
    text: children.map((child) => child.text).filter(Boolean).join('\n'),
    source: children.some((child) => child.text && child.source === 'html') ? 'html' : 'plain_text',
    unsupported: children.some((child) => child.unsupported),
    truncated: children.some((child) => child.truncated),
  };
}

function extractMessageEvidence(message, maxSerializedBytes = 32768) {
  const body = messageBody(message.payload, { remaining: MAX_MIME_PARTS });
  const source = body.text || message.snippet || '';
  let end = Math.min(source.length, MAX_EVIDENCE_CHARACTERS);
  let start = 0;
  while (start < end) {
    const middle = Math.ceil((start + end) / 2);
    if (Buffer.byteLength(JSON.stringify(source.slice(0, middle))) <= maxSerializedBytes) {
      start = middle;
    } else {
      end = middle - 1;
    }
  }
  // Do not cut a UTF-16 surrogate pair at either evidence limit.
  if (start > 0 && /[\uD800-\uDBFF]/.test(source[start - 1])) start--;
  return {
    snippet: source.slice(0, start),
    contentSource: body.text ? body.source : 'snippet',
    contentStatus: body.truncated || start < source.length
      ? 'truncated'
      : (body.unsupported ? 'unsupported' : (body.text ? 'complete' : 'snippet_only')),
  };
}

module.exports = { extractMessageEvidence };
