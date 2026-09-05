const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const lambdaDirectory = path.resolve(__dirname, '..');
const archive = path.join(lambdaDirectory, 'lambda.zip');

function archiveEntry(name) {
  return execFileSync('unzip', ['-p', archive, name], { encoding: 'utf8' });
}

function loadArchivedModule(name, dependencies) {
  const module = { exports: {} };
  vm.runInNewContext(archiveEntry(name), {
    module,
    exports: module.exports,
    require: (dependency) => dependencies[dependency],
    Buffer,
  }, { filename: name });
  return module.exports;
}

test('deployed Lambda handler sends a bounded Gmail scan query to Gmail', async () => {
  const requests = [];
  const noOpCommand = class {
    constructor(input) {
      this.input = input;
    }
  };
  const gmailScanQuery = loadArchivedModule('gmail_scan_query.js', {});
  const analyticsReports = loadArchivedModule('analytics_reports.js', {});
  const https = {
    get(options, callback) {
      requests.push(options);
      callback({
        statusCode: 200,
        on(event, listener) {
          if (event === 'data') listener('{"messages":[]}');
          if (event === 'end') listener();
        },
      });
      return { on() {} };
    },
  };
  const handlerModule = { exports: {} };
  vm.runInNewContext(archiveEntry('index.js'), {
    module: handlerModule,
    exports: handlerModule.exports,
    require(dependency) {
      if (dependency === 'https') return https;
      if (dependency === '@aws-sdk/client-dynamodb') {
        return { BatchWriteItemCommand: noOpCommand, DynamoDBClient: noOpCommand };
      }
      if (dependency === '@aws-sdk/lib-dynamodb') {
        return {
          DynamoDBDocumentClient: { from: () => ({ send: async () => ({}) }) },
          PutCommand: noOpCommand,
          QueryCommand: noOpCommand,
        };
      }
      if (dependency === '@aws-sdk/client-secrets-manager') {
        return { GetSecretValueCommand: noOpCommand, SecretsManagerClient: noOpCommand };
      }
      if (dependency === './auth_identity') {
        return { resolveGatewayAuthenticatedUserPk: () => 'USER#owner' };
      }
      if (dependency === './dynamodb_pagination') return {};
      if (dependency === './gmail_scan_query') return gmailScanQuery;
      if (dependency === './gmail_message_evidence') {
        return loadArchivedModule('gmail_message_evidence.js', { 'node:util': require('node:util') });
      }
      if (dependency === './analytics_reports') return analyticsReports;
      if (dependency === './runtime_config') return {};
      throw new Error(`Unexpected dependency: ${dependency}`);
    },
    process: { env: {} },
    console: { log() {}, warn() {} },
    URL,
  }, { filename: 'index.js' });

  const response = await handlerModule.exports.handler({
    rawPath: '/api/gmail/scan',
    requestContext: { http: { method: 'POST' } },
    headers: { 'x-gmail-token': 'test-token' },
    body: JSON.stringify({
      afterTimestamp: 1724889600,
      beforeTimestamp: 1724976000,
      maxResults: 250,
    }),
  });

  assert.equal(response.statusCode, 200);
  const responseBody = JSON.parse(response.body);
  assert.equal(responseBody.extractionMode, 'none');
  assert.equal(responseBody.fallbackReason, null);
  assert.equal(requests.length, 1);
  const requestUrl = new URL(`https://gmail.googleapis.com${requests[0].path}`);
  assert.equal(
    requestUrl.searchParams.get('q'),
    'after:1724889600 before:1724976000 (alert OR statement OR debited OR credited OR transaction OR "spent" OR "bill" OR "card" OR "vpa" OR "upi" OR "inr" OR "rs")',
  );
  assert.equal(requestUrl.searchParams.get('maxResults'), '250');
});

test('deployed Lambda reports why deterministic fallback was selected', async () => {
  const noOpCommand = class {
    constructor(input) {
      this.input = input;
    }
  };
  const gmailScanQuery = loadArchivedModule('gmail_scan_query.js', {});
  const analyticsReports = loadArchivedModule('analytics_reports.js', {});
  const logs = [];
  const https = {
    get(options, callback) {
      callback({
        statusCode: 200,
        on(event, listener) {
          if (event === 'data') {
            listener(options.path.includes('/messages?')
              ? '{"messages":[{"id":"message-1"}]}'
              : '{"id":"message-1","payload":{"headers":[]},"snippet":"debited INR 100"}');
          }
          if (event === 'end') listener();
        },
      });
      return { on() {} };
    },
  };
  const handlerModule = { exports: {} };
  vm.runInNewContext(archiveEntry('index.js'), {
    module: handlerModule,
    exports: handlerModule.exports,
    require(dependency) {
      if (dependency === 'https') return https;
      if (dependency === '@aws-sdk/client-dynamodb') {
        return { BatchWriteItemCommand: noOpCommand, DynamoDBClient: noOpCommand };
      }
      if (dependency === '@aws-sdk/lib-dynamodb') {
        return {
          DynamoDBDocumentClient: { from: () => ({ send: async () => ({}) }) },
          PutCommand: noOpCommand,
          QueryCommand: noOpCommand,
        };
      }
      if (dependency === '@aws-sdk/client-secrets-manager') {
        return { GetSecretValueCommand: noOpCommand, SecretsManagerClient: noOpCommand };
      }
      if (dependency === './auth_identity') {
        return { resolveGatewayAuthenticatedUserPk: () => 'USER#owner' };
      }
      if (dependency === './dynamodb_pagination') return {};
      if (dependency === './gmail_scan_query') return gmailScanQuery;
      if (dependency === './gmail_message_evidence') {
        return loadArchivedModule('gmail_message_evidence.js', { 'node:util': require('node:util') });
      }
      if (dependency === './analytics_reports') return analyticsReports;
      if (dependency === './runtime_config') return {};
      throw new Error(`Unexpected dependency: ${dependency}`);
    },
    process: { env: {} },
    console: {
      log(...args) { logs.push(args); },
      warn(...args) { logs.push(args); },
      error(...args) { logs.push(args); },
    },
    URL,
  }, { filename: 'index.js' });

  const response = await handlerModule.exports.handler({
    rawPath: '/api/gmail/scan',
    requestContext: { http: { method: 'POST' }, requestId: 'correlation-1' },
    headers: { 'x-gmail-token': 'test-token' },
    body: '{}',
  });

  const responseBody = JSON.parse(response.body);
  assert.equal(response.statusCode, 200);
  assert.equal(responseBody.extractionMode, 'deterministic_fallback');
  assert.equal(responseBody.fallbackReason, 'gemini_api_key_unavailable');
  assert.ok(logs.some(([message, details]) =>
    message === '[GMAIL_SCAN] Using deterministic fallback parser' &&
    details.correlationId === 'correlation-1' &&
    details.fallbackReason === 'gemini_api_key_unavailable'));
});
