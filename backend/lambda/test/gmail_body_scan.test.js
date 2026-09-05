const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const lambdaDirectory = path.resolve(__dirname, '..');
const transactionText =
  'INR 103.00 spent at UPI_MUMBAI_TESTSHOP on YES BANK credit card (1234).';

function textPart(text, mimeType = 'text/plain', extra = {}) {
  return {
    mimeType,
    body: { data: Buffer.from(text).toString('base64url') },
    ...extra,
  };
}

async function scanMessage(payload, { snippet = 'Dear customer', ai = false, messageCount = 1 } = {}) {
  const logs = [];
  const modelRequests = [];
  class Command {
    constructor(input) { this.input = input; }
  }
  function respond(callback, body) {
    callback({
      statusCode: 200,
      on(event, listener) {
        if (event === 'data') listener(JSON.stringify(body));
        if (event === 'end') listener();
      },
    });
  }
  const https = {
    get(options, callback) {
      const url = new URL(`https://${options.hostname}${options.path}`);
      if (url.pathname.endsWith('/messages')) {
        respond(callback, {
          messages: Array.from({ length: messageCount }, (_, index) => ({
            id: index === 0 ? 'fictional-email' : `fictional-email-${index}`,
          })),
        });
      } else {
        respond(callback, {
          snippet,
          internalDate: '1786838400000',
          payload: {
            ...(url.searchParams.get('format') === 'full' ? payload : {}),
            headers: [
              { name: 'Subject', value: 'YES BANK - transaction alert' },
              { name: 'From', value: 'alerts@example.invalid' },
              ...(payload.headers || []),
            ],
          },
        });
      }
      return { on() {} };
    },
    request(options, callback) {
      let data = '';
      return {
        on() {},
        write(chunk) { data += chunk; },
        end() {
          modelRequests.push(JSON.parse(data));
          respond(callback, {
            candidates: [{ content: { parts: [{ text: JSON.stringify({
              items: [{
                id: 'fictional-email',
                isFinancialTransaction: true,
                merchant: 'UPI_MUMBAI_TESTSHOP',
                amount: 103,
                type: 'DEBIT',
                accountType: 'CREDIT_CARD',
                accountMask: '1234',
              }],
            }) }] } }],
          });
        },
      };
    },
  };
  const module = { exports: {} };
  vm.runInNewContext(fs.readFileSync(path.join(lambdaDirectory, 'index.js'), 'utf8'), {
    module,
    exports: module.exports,
    require(dependency) {
      if (dependency === 'https') return https;
      if (dependency === '@aws-sdk/client-dynamodb') {
        return { BatchWriteItemCommand: Command, DynamoDBClient: Command };
      }
      if (dependency === '@aws-sdk/lib-dynamodb') {
        return {
          DynamoDBDocumentClient: { from: () => ({
            send: async () => { throw new Error('Scanning must not write ledger data'); },
          }) },
          PutCommand: Command,
          QueryCommand: Command,
        };
      }
      if (dependency === '@aws-sdk/client-secrets-manager') {
        return {
          GetSecretValueCommand: Command,
          SecretsManagerClient: class {
            async send() { return { SecretString: 'fictional-test-key' }; }
          },
        };
      }
      if (dependency.startsWith('./')) return require(path.join(lambdaDirectory, dependency));
      throw new Error(`Unexpected dependency: ${dependency}`);
    },
    process: { env: ai ? { GEMINI_SECRET_ARN: 'test-secret' } : {} },
    console: {
      log(...args) { logs.push(args); },
      warn(...args) { logs.push(args); },
      error(...args) { logs.push(args); },
    },
    URL,
    Buffer,
  }, { filename: 'index.js' });

  const response = await module.exports.handler({
    rawPath: '/api/gmail/scan',
    requestContext: {
      http: { method: 'POST' },
      requestId: 'body-evidence-test',
      authorizer: { jwt: { claims: {
        email: 'fixture@example.invalid', email_verified: true,
      } } },
    },
    headers: { 'x-gmail-token': 'fictional-token' },
    body: JSON.stringify({ maxResults: 1 }),
  });
  assert.equal(response.statusCode, 200);
  return {
    result: JSON.parse(response.body),
    logs,
    modelRequests,
    responseBytes: Buffer.byteLength(JSON.stringify(response)),
  };
}

test('scan extracts a payment below a long greeting and returns its body as review evidence', async () => {
  const body = `Dear customer,\n${'Your account information. '.repeat(25)}\n${transactionText}`;
  const { result, logs } = await scanMessage(textPart(body));

  assert.equal(result.transactionCandidates.length, 1);
  const candidate = result.transactionCandidates[0];
  assert.equal(candidate.merchantName, 'UPI_MUMBAI_TESTSHOP');
  assert.equal(candidate.amount, 103);
  assert.equal(candidate.snippet, body);
  assert.equal(candidate.contentSource, 'plain_text');
  assert.equal(candidate.contentStatus, 'complete');
  assert.equal(result.rawScannedEmails[0].snippet, body);
  assert.ok(!JSON.stringify(logs).includes(transactionText));
});

test('scan supplies the same body evidence to Gemini and transaction review', async () => {
  const body = `Dear customer,\n${'Your account information. '.repeat(25)}\n${transactionText}`;
  const { result, modelRequests } = await scanMessage(textPart(body), { ai: true });

  const prompt = modelRequests[0].contents[0].parts[0].text;
  assert.ok(prompt.includes(transactionText), 'Gemini must receive the body-only payment detail');
  assert.ok(prompt.includes('"contentSource":"plain_text"'));
  assert.ok(prompt.includes('"contentStatus":"complete"'));
  assert.equal(result.transactionCandidates[0].snippet, body);
});

test('scan reads nested plain-text alternatives but excludes file and forwarded-message attachments', async () => {
  const { result } = await scanMessage({
    mimeType: 'multipart/mixed',
    parts: [
      textPart('INR 999.00 spent at ATTACHMENT_SHOP on card (9876).', 'text/plain', {
        filename: 'receipt.txt',
      }),
      {
        mimeType: 'message/rfc822',
        parts: [textPart('INR 999.00 spent at FORWARDED_SHOP on card (9876).')],
      },
      {
        mimeType: 'multipart/alternative',
        parts: [
          textPart('<p>HTML_ALTERNATIVE_SHOP</p>', 'text/html'),
          textPart(transactionText),
        ],
      },
    ],
  });

  assert.equal(result.transactionCandidates.length, 1);
  assert.equal(result.transactionCandidates[0].merchantName, 'UPI_MUMBAI_TESTSHOP');
  assert.equal(result.transactionCandidates[0].snippet, transactionText);
  assert.equal(result.rawScannedEmails[0].contentStatus, 'complete');
});

test('scan converts HTML-only body evidence to readable text without scripts or styles', async () => {
  const { result } = await scanMessage({
    mimeType: 'multipart/related',
    parts: [
      textPart('<html><head><style>.offer { color: red }</style></head><body>' +
        '<script>INR 999.00 spent at SCRIPT_SHOP on card (9876).</script>' +
        '<!-- PROMO -->' +
        '<p>Dear customer,&nbsp;here are your details.</p>' +
        '<table><tr><td>INR&nbsp;103.00</td><td>spent at ' +
        '<b>UPI_MUMBAI_TESTSHOP</b> on YES BANK credit card (1234).</td></tr></table>' +
        '<p>Reference: A&amp;B &#x26; C &#38; D</p></body></html>', 'text/html'),
      { mimeType: 'image/png', filename: 'logo.png', body: { attachmentId: 'ignored' } },
    ],
  });

  assert.equal(result.transactionCandidates.length, 1);
  const candidate = result.transactionCandidates[0];
  assert.equal(candidate.merchantName, 'UPI_MUMBAI_TESTSHOP');
  assert.equal(candidate.amount, 103);
  assert.equal(candidate.contentSource, 'html');
  assert.equal(candidate.contentStatus, 'complete');
  assert.match(candidate.snippet, /Reference: A&B & C & D/);
  assert.doesNotMatch(candidate.snippet, /<|SCRIPT_SHOP|PROMO|color: red/);
});

test('scan explicitly marks unavailable or unsupported body evidence instead of claiming completeness', async () => {
  const cases = [
    [{}, 'snippet_only'],
    [{ mimeType: 'text/plain', body: { attachmentId: 'body-not-inlined' } }, 'unsupported'],
    [{ mimeType: 'text/plain', body: { data: '%%%invalid%%%' } }, 'unsupported'],
    [textPart(transactionText, 'text/plain', {
      headers: [{ name: 'Content-Type', value: 'text/plain; charset=unknown-charset' }],
    }), 'unsupported'],
    [{
      mimeType: 'multipart/mixed',
      parts: [
        textPart(transactionText),
        { mimeType: 'text/plain', body: { attachmentId: 'missing-body-section' } },
      ],
    }, 'unsupported'],
  ];
  for (const [payload, status] of cases) {
    const { result } = await scanMessage(payload, { snippet: transactionText });
    assert.equal(result.rawScannedEmails[0].contentStatus, status);
    assert.equal(result.transactionCandidates[0].contentStatus, status);
    assert.equal(result.transactionCandidates[0].snippet, transactionText);
  }
});

test('scan bounds large bodies and MIME traversal and exposes truncation to review and Gemini', async () => {
  let nested = textPart(transactionText);
  for (let depth = 0; depth < 20; depth++) {
    nested = { mimeType: 'multipart/mixed', parts: [nested] };
  }
  const cases = [
    textPart(`${transactionText}\n${'x'.repeat(10000)}`),
    textPart(`<style>${'x'.repeat(100000)}</style><p>${transactionText}</p>`, 'text/html'),
    nested,
    {
      mimeType: 'multipart/mixed',
      parts: [textPart(transactionText), ...Array.from({ length: 100 }, () => textPart('detail'))],
    },
  ];
  for (const payload of cases) {
    const { result, modelRequests } = await scanMessage(payload, { snippet: transactionText, ai: true });
    const evidence = result.rawScannedEmails[0];
    assert.equal(evidence.contentStatus, 'truncated');
    assert.ok(evidence.snippet.length <= 8000);
    assert.equal(result.transactionCandidates[0].contentStatus, 'truncated');
    assert.equal(result.transactionCandidates[0].snippet, evidence.snippet);
    assert.ok(modelRequests[0].contents[0].parts[0].text.includes('"contentStatus":"truncated"'));
  }
});

test('a maximum-size scan keeps duplicated review evidence within the Lambda response budget', async () => {
  const { result, responseBytes } = await scanMessage(
    textPart(`${transactionText}\n${'\u20b9"\\'.repeat(3000)}`),
    { messageCount: 500 },
  );
  assert.equal(result.emailsScanned, 500);
  assert.equal(result.transactionCandidates.length, 500);
  assert.ok(responseBytes < 6 * 1024 * 1024, `Lambda response is ${responseBytes} bytes`);
  assert.equal(result.rawScannedEmails.at(-1).contentStatus, 'truncated');
  assert.match(result.rawScannedEmails.at(-1).snippet, /UPI_MUMBAI_TESTSHOP/);
});

test('scan handles malformed HTML within a bounded processing time', async () => {
  const start = performance.now();
  const { result } = await scanMessage(textPart('<'.repeat(49000), 'text/html'));
  assert.equal(result.emailsScanned, 1);
  assert.ok(performance.now() - start < 1000, 'Malformed tags must not stall the scan');
});

test('HTML body extraction preserves Unicode text without shifting tag boundaries', async () => {
  const { result } = await scanMessage(textPart(
    `\u0130stanbul<script>INR 999.00 spent at SCRIPT_SHOP on card (9876).</script><p>${transactionText}</p>`,
    'text/html',
  ));
  assert.equal(result.transactionCandidates[0].merchantName, 'UPI_MUMBAI_TESTSHOP');
  assert.match(result.transactionCandidates[0].snippet, /\u0130stanbul/);
  assert.doesNotMatch(result.transactionCandidates[0].snippet, /SCRIPT_SHOP/);
});
