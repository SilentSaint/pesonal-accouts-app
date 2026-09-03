const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.resolve(__dirname, '..', 'websocket_sync.js'),
  'utf8',
);

class Command {
  constructor(input) {
    this.input = input;
  }
}

function loadSyncModule() {
  const module = { exports: {} };
  vm.runInNewContext(source, {
    module,
    exports: module.exports,
    require(dependency) {
      if (dependency === '@aws-sdk/lib-dynamodb') {
        return {
          DeleteCommand: Command,
          GetCommand: Command,
          PutCommand: Command,
          QueryCommand: Command,
        };
      }
      if (dependency === '@aws-sdk/client-apigatewaymanagementapi') {
        return {
          ApiGatewayManagementApiClient: class {},
          PostToConnectionCommand: Command,
        };
      }
      if (dependency === '@aws-sdk/client-dynamodb') {
        return { DynamoDBClient: class {} };
      }
      throw new Error(`Unexpected dependency: ${dependency}`);
    },
    Buffer,
    JSON,
    process: { env: {} },
  }, { filename: 'websocket_sync.js' });
  return module.exports;
}

test('connect stores a connection only under the authenticated user scope', async () => {
  const { createWebSocketSyncHandler } = loadSyncModule();
  const commands = [];
  const handler = createWebSocketSyncHandler({
    tableName: 'ExpenseTrackerData',
    ddb: { send: async (command) => commands.push(command.input) },
    managementClient: { send: async () => {} },
  });

  const response = await handler({
    requestContext: {
      routeKey: '$connect',
      connectionId: 'web-client-1',
      authorizer: { userPk: 'USER#owner' },
    },
  });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(JSON.stringify(commands)), [
    {
      TableName: 'ExpenseTrackerData',
      Item: {
        PK: 'WSUSER#USER#owner',
        SK: 'CONNECTION#web-client-1',
        connectionId: 'web-client-1',
      },
    },
    {
      TableName: 'ExpenseTrackerData',
      Item: {
        PK: 'WSCONNECTION#web-client-1',
        SK: 'CONNECTION',
        userPk: 'USER#owner',
      },
    },
  ]);
});

test('fails with a configuration error when a broadcast has no websocket endpoint', async () => {
  const { publishCanonicalSyncEvent } = loadSyncModule();

  await assert.rejects(
    publishCanonicalSyncEvent({
      tableName: 'ExpenseTrackerData',
      ddb: { send: async () => ({ Items: [] }) },
      userPk: 'USER#owner',
      event: { type: 'ENTITY_UPSERTED', entityId: 'entity-1', payload: { id: 'entity-1' } },
    }),
    { message: 'WEBSOCKET_MANAGEMENT_ENDPOINT is not configured' },
  );
});

test('broadcast reaches only a user’s active connections and removes gone connections', async () => {
  const { publishCanonicalSyncEvent } = loadSyncModule();
  const commands = [];
  const posted = [];
  const ddb = {
    send: async (command) => {
      commands.push(command.input);
      if (command.input.KeyConditionExpression) {
        return {
          Items: [
            { connectionId: 'mobile-1' },
            { connectionId: 'stale-browser' },
          ],
        };
      }
      return {};
    },
  };
  const managementClient = {
    send: async (command) => {
      posted.push(command.input);
      if (command.input.ConnectionId === 'stale-browser') {
        const error = new Error('Gone');
        error.$metadata = { httpStatusCode: 410 };
        throw error;
      }
    },
  };

  await publishCanonicalSyncEvent({
    tableName: 'ExpenseTrackerData',
    ddb,
    managementClient,
    userPk: 'USER#owner',
    event: {
      type: 'TRANSACTION_UPSERTED',
      entityId: 'txn-42',
      payload: { id: 'txn-42', amount: 450 },
      occurredAt: '2026-08-29T06:00:00.000Z',
    },
  });

  assert.deepEqual(
    posted.map((request) => request.ConnectionId),
    ['mobile-1', 'stale-browser'],
  );
  assert.deepEqual(
    JSON.parse(Buffer.from(posted[0].Data).toString('utf8')),
    {
      version: 1,
      type: 'TRANSACTION_UPSERTED',
      entityId: 'txn-42',
      payload: { id: 'txn-42', amount: 450 },
      occurredAt: '2026-08-29T06:00:00.000Z',
    },
  );
  assert.deepEqual(JSON.parse(JSON.stringify(commands.slice(1))), [
    {
      TableName: 'ExpenseTrackerData',
      Key: {
        PK: 'WSUSER#USER#owner',
        SK: 'CONNECTION#stale-browser',
      },
    },
    {
      TableName: 'ExpenseTrackerData',
      Key: {
        PK: 'WSCONNECTION#stale-browser',
        SK: 'CONNECTION',
      },
    },
  ]);
});

test('two clients receive an owner mutation and a reconnected client receives the recovery event', async () => {
  const { createWebSocketSyncHandler, publishCanonicalSyncEvent } =
      loadSyncModule();
  const items = new Map();
  const deliveries = new Map();
  const ddb = {
    send: async (command) => {
      const request = command.input;
      if (request.Item) {
        items.set(`${request.Item.PK}|${request.Item.SK}`, request.Item);
        return {};
      }
      if (request.KeyConditionExpression) {
        return {
          Items: [...items.values()].filter((item) =>
            item.PK === request.ExpressionAttributeValues[':pk'] &&
            item.SK.startsWith('CONNECTION#')),
        };
      }
      if (request.Key) {
        const key = `${request.Key.PK}|${request.Key.SK}`;
        if (request.TableName && request.Key.PK.startsWith('WSCONNECTION')) {
          return { Item: items.get(key) };
        }
        items.delete(key);
      }
      return {};
    },
  };
  const managementClient = {
    send: async (command) => {
      const event = JSON.parse(Buffer.from(command.input.Data).toString('utf8'));
      deliveries.set(
        command.input.ConnectionId,
        [...(deliveries.get(command.input.ConnectionId) || []), event],
      );
    },
  };
  const handler = createWebSocketSyncHandler({
    tableName: 'ExpenseTrackerData',
    ddb,
    managementClient,
  });
  const connect = (connectionId, userPk) => handler({
    requestContext: { routeKey: '$connect', connectionId, authorizer: { userPk } },
  });

  await connect('phone', 'USER#owner');
  await connect('browser', 'USER#owner');
  await connect('other-user', 'USER#other');
  await publishCanonicalSyncEvent({
    tableName: 'ExpenseTrackerData',
    ddb,
    managementClient,
    userPk: 'USER#owner',
    event: { type: 'TRANSACTION_UPSERTED', entityId: 'txn-42', payload: { id: 'txn-42' } },
  });
  await handler({ requestContext: { routeKey: '$disconnect', connectionId: 'phone' } });
  await connect('phone-reconnected', 'USER#owner');
  await publishCanonicalSyncEvent({
    tableName: 'ExpenseTrackerData',
    ddb,
    managementClient,
    userPk: 'USER#owner',
    event: { type: 'TRANSACTION_UPSERTED', entityId: 'txn-43', payload: { id: 'txn-43' } },
  });

  assert.deepEqual(
    deliveries.get('browser').map((event) => event.entityId),
    ['txn-42', 'txn-43'],
  );
  assert.deepEqual(
    deliveries.get('phone-reconnected').map((event) => event.entityId),
    ['txn-43'],
  );
  assert.equal(deliveries.has('other-user'), false);
});
