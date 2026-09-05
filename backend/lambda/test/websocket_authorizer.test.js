const assert = require('node:assert/strict');
const test = require('node:test');

const { createWebSocketAuthorizer } = require('../websocket_authorizer');

test('authorizer grants an email-verified Google identity and scopes its connection', async () => {
  const handler = createWebSocketAuthorizer({
    clientId: 'expected-client-id',
    fetchTokenInfo: async () => ({
      aud: 'expected-client-id',
      email: 'owner@example.com',
      email_verified: 'true',
    }),
  });

  const result = await handler({
    methodArn: 'arn:aws:execute-api:ap-south-2:123456789012:api/dev/$connect',
    queryStringParameters: { token: 'google-id-token' },
  });

  assert.equal(result.policyDocument.Statement[0].Effect, 'Allow');
  assert.equal(result.context.userPk, 'USER#c8cd3c6427301eaf6665bccacd65ddb6');
});

test('authorizer rejects an unverified or wrong-audience identity token', async () => {
  const handler = createWebSocketAuthorizer({
    clientId: 'expected-client-id',
    fetchTokenInfo: async () => ({
      aud: 'another-client-id',
      email: 'owner@example.com',
      email_verified: 'false',
    }),
  });

  const result = await handler({
    methodArn: 'arn:aws:execute-api:ap-south-2:123456789012:api/dev/$connect',
    queryStringParameters: { token: 'invalid-token' },
  });

  assert.equal(result.policyDocument.Statement[0].Effect, 'Deny');
  assert.deepEqual(result.context, {});
});
