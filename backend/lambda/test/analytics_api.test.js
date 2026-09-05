const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const lambdaDirectory = path.resolve(__dirname, '..');

function loadHandler(send) {
  const source = fs.readFileSync(path.join(lambdaDirectory, 'index.js'), 'utf8');
  const module = { exports: {} };
  class Command {
    constructor(input) {
      this.input = input;
    }
  }
  vm.runInNewContext(source, {
    module,
    exports: module.exports,
    require(dependency) {
      if (dependency === 'https') return {};
      if (dependency === '@aws-sdk/client-dynamodb') {
        return { BatchWriteItemCommand: Command, DynamoDBClient: class {} };
      }
      if (dependency === '@aws-sdk/lib-dynamodb') {
        return {
          DynamoDBDocumentClient: { from: () => ({ send }) },
          PutCommand: Command,
          QueryCommand: Command,
        };
      }
      if (dependency === '@aws-sdk/client-secrets-manager') {
        return { GetSecretValueCommand: Command, SecretsManagerClient: class {} };
      }
      if (dependency === './auth_identity') {
        return { resolveGatewayAuthenticatedUserPk: (event) =>
          event.requestContext?.authorizer?.jwt?.claims?.email_verified === 'true'
            ? 'USER#verified-owner'
            : null };
      }
      if (dependency === './analytics_reports') return require('../analytics_reports');
      if (dependency === './dynamodb_pagination') return {};
      if (dependency === './gmail_scan_query' || dependency === './runtime_config') return {};
      if (dependency === './gmail_message_evidence') return require('../gmail_message_evidence');
      throw new Error(`Unexpected dependency: ${dependency}`);
    },
    process: { env: {} },
    console: { log() {}, warn() {}, error() {} },
    Buffer,
    URL,
    setTimeout,
  }, { filename: 'index.js' });
  return module.exports.handler;
}

function authenticatedEvent(pathname, queryStringParameters = {}) {
  return {
    rawPath: pathname,
    queryStringParameters,
    requestContext: {
      http: { method: 'GET' },
      authorizer: { jwt: { claims: { email_verified: 'true' } } },
    },
  };
}

test('analytics API scopes its DynamoDB query and returns derived report contents', async () => {
  const commands = [];
  const handler = loadHandler(async (command) => {
    commands.push(command.input);
    return {
      Items: [{
        data: {
          id: 'debit-1',
          amount: 200,
          netPersonalExpense: 125,
          currency: 'INR',
          type: 'DEBIT',
          merchantName: 'Server Cafe',
          categoryId: 'Dining',
          timestamp: '2026-08-04T09:00:00.000Z',
        },
      }],
    };
  });

  const response = await handler(authenticatedEvent('/api/analytics', { month: '2026-08' }));
  const body = JSON.parse(response.body);

  assert.equal(response.statusCode, 200);
  assert.equal(commands[0].ExpressionAttributeValues[':pk'], 'USER#verified-owner');
  assert.deepEqual(body.cashFlow, {
    income: 0,
    spending: 200,
    netPersonalExpense: 125,
    netSavings: -125,
  });
  assert.equal(body.categoryTotals[0].total, 125);
});

test('analytics export API returns a CSV attachment with selected persisted transactions', async () => {
  const handler = loadHandler(async () => ({
    Items: [{
      data: {
        id: 'debit-1',
        amount: 200,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Server Cafe',
        categoryId: 'Dining',
        timestamp: '2026-08-04T09:00:00.000Z',
      },
    }],
  }));

  const response = await handler(authenticatedEvent('/api/analytics/export', {
    month: '2026-08',
    format: 'csv',
  }));

  assert.equal(response.statusCode, 200);
  assert.equal(response.isBase64Encoded, true);
  assert.equal(response.headers['Content-Disposition'], 'attachment; filename="financial-report-2026-08.csv"');
  assert.match(Buffer.from(response.body, 'base64').toString('utf8'), /"Server Cafe"/);
});
