const {
  DeleteCommand,
  GetCommand,
  PutCommand,
  QueryCommand,
} = require('@aws-sdk/lib-dynamodb');
const {
  ApiGatewayManagementApiClient,
  PostToConnectionCommand,
} = require('@aws-sdk/client-apigatewaymanagementapi');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient } = require('@aws-sdk/lib-dynamodb');

function userConnectionKey(userPk, connectionId) {
  return {
    PK: `WSUSER#${userPk}`,
    SK: `CONNECTION#${connectionId}`,
  };
}

function reverseConnectionKey(connectionId) {
  return {
    PK: `WSCONNECTION#${connectionId}`,
    SK: 'CONNECTION',
  };
}

async function removeConnection({ ddb, tableName, userPk, connectionId }) {
  await Promise.all([
    ddb.send(new DeleteCommand({
      TableName: tableName,
      Key: userConnectionKey(userPk, connectionId),
    })),
    ddb.send(new DeleteCommand({
      TableName: tableName,
      Key: reverseConnectionKey(connectionId),
    })),
  ]);
}

function isGoneConnection(error) {
  return error?.$metadata?.httpStatusCode === 410 || error?.name === 'GoneException';
}

function createManagementClient() {
  const endpoint = process.env.WEBSOCKET_MANAGEMENT_ENDPOINT;
  if (!endpoint) {
    throw new Error('WEBSOCKET_MANAGEMENT_ENDPOINT is not configured');
  }
  return new ApiGatewayManagementApiClient({ endpoint });
}

async function publishCanonicalSyncEvent({
  ddb,
  managementClient,
  tableName,
  userPk,
  event,
}) {
  const activeManagementClient = managementClient || createManagementClient();
  const connections = await ddb.send(new QueryCommand({
    TableName: tableName,
    KeyConditionExpression: 'PK = :pk AND begins_with(SK, :connectionPrefix)',
    ExpressionAttributeValues: {
      ':pk': `WSUSER#${userPk}`,
      ':connectionPrefix': 'CONNECTION#',
    },
    ProjectionExpression: 'connectionId',
  }));
  const message = Buffer.from(JSON.stringify({
    version: 1,
    type: event.type,
    entityId: event.entityId,
    payload: event.payload,
    occurredAt: event.occurredAt || new Date().toISOString(),
  }));

  await Promise.all((connections.Items || []).map(async ({ connectionId }) => {
    try {
      await activeManagementClient.send(new PostToConnectionCommand({
        ConnectionId: connectionId,
        Data: message,
      }));
    } catch (error) {
      if (isGoneConnection(error)) {
        await removeConnection({ ddb, tableName, userPk, connectionId });
        return;
      }

      throw error;
    }
  }));
}

function createWebSocketSyncHandler({ tableName, ddb, managementClient }) {
  return async (event) => {
    const routeKey = event?.requestContext?.routeKey;
    const connectionId = event?.requestContext?.connectionId;
    if (!connectionId) return { statusCode: 400, body: 'Missing connection ID' };

    if (routeKey === '$connect') {
      const userPk = event.requestContext.authorizer?.userPk;
      if (typeof userPk !== 'string' || !userPk.startsWith('USER#')) {
        return { statusCode: 401, body: 'Unauthenticated connection' };
      }
      await Promise.all([
        ddb.send(new PutCommand({
          TableName: tableName,
          Item: { ...userConnectionKey(userPk, connectionId), connectionId },
        })),
        ddb.send(new PutCommand({
          TableName: tableName,
          Item: { ...reverseConnectionKey(connectionId), userPk },
        })),
      ]);
      return { statusCode: 200, body: 'Connected' };
    }

    if (routeKey === '$disconnect') {
      const existing = await ddb.send(new GetCommand({
        TableName: tableName,
        Key: reverseConnectionKey(connectionId),
      }));
      if (existing.Item?.userPk) {
        await removeConnection({
          ddb,
          tableName,
          userPk: existing.Item.userPk,
          connectionId,
        });
      }
      return { statusCode: 200, body: 'Disconnected' };
    }

    return { statusCode: 200, body: 'OK' };
  };
}

module.exports = {
  createWebSocketSyncHandler,
  publishCanonicalSyncEvent,
  handler: async (event) => {
    const tableName = process.env.TABLE_NAME || 'ExpenseTrackerData';
    const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
    const managementClient = createManagementClient();
    return createWebSocketSyncHandler({ tableName, ddb, managementClient })(event);
  },
};
