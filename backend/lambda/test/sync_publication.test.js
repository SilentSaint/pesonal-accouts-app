const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

class Command {
  constructor(input) {
    this.input = input;
  }
}

test('an authenticated transaction mutation publishes its canonical sync event', async () => {
  const source = fs.readFileSync(path.resolve(__dirname, '..', 'index.js'), 'utf8');
  const module = { exports: {} };
  const published = [];
  vm.runInNewContext(source, {
    module,
    exports: module.exports,
    require(dependency) {
      if (dependency === '@aws-sdk/client-dynamodb') {
        return { BatchWriteItemCommand: Command, DynamoDBClient: class {} };
      }
      if (dependency === '@aws-sdk/lib-dynamodb') {
        return {
          DynamoDBDocumentClient: { from: () => ({ send: async () => ({}) }) },
          PutCommand: Command,
          QueryCommand: Command,
        };
      }
      if (dependency === '@aws-sdk/client-secrets-manager') {
        return { GetSecretValueCommand: Command, SecretsManagerClient: class {} };
      }
      if (dependency === './auth_identity') {
        return { resolveGatewayAuthenticatedUserPk: () => 'USER#owner' };
      }
      if (dependency === './websocket_sync') {
        return {
          publishCanonicalSyncEvent: async (event) => published.push(event),
        };
      }
      if (dependency === './dynamodb_pagination') {
        return { transactionSortKey: (transaction) => `TXN#${transaction.id}` };
      }
      if (
        dependency === './analytics_reports' ||
        dependency === './gmail_scan_query' ||
        dependency === './runtime_config'
      ) {
        return {};
      }
      if (dependency === 'https') return {};
      if (dependency === './gmail_message_evidence') return require('../gmail_message_evidence');
      throw new Error(`Unexpected dependency: ${dependency}`);
    },
    process: { env: {} },
    console: { log() {}, warn() {}, error() {} },
    Buffer,
    URL,
    setTimeout,
  }, { filename: 'index.js' });

  const response = await module.exports.handler({
    rawPath: '/api/transactions',
    body: '{"id":"txn-42","amount":450}',
    requestContext: { http: { method: 'POST' } },
  });

  assert.equal(response.statusCode, 201);
  assert.equal(published.length, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(published[0].event)), {
    type: 'TRANSACTION_UPSERTED',
    entityId: 'txn-42',
    payload: { id: 'txn-42', amount: 450 },
  });
  assert.equal(published[0].userPk, 'USER#owner');
});
