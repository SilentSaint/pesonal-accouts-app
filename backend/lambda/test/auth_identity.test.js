const assert = require('node:assert/strict');
const test = require('node:test');

const {
  resolveGatewayAuthenticatedUserPk,
} = require('../auth_identity');

test('derives the partition key only from verified API Gateway JWT claims', () => {
  const userPk = resolveGatewayAuthenticatedUserPk({
    requestContext: {
      authorizer: {
        jwt: {
          claims: { email: 'owner@example.com', email_verified: 'true' },
        },
      },
    },
  });

  assert.equal(userPk, 'USER#c8cd3c6427301eaf6665bccacd65ddb6');
});

test('rejects unverified email claims even when an authorization header is present', () => {
  const userPk = resolveGatewayAuthenticatedUserPk({
    headers: {
      authorization: 'Bearer untrusted-token',
      'x-user-id': 'USER#another-user',
    },
    requestContext: {
      authorizer: {
        jwt: {
          claims: { email: 'owner@example.com', email_verified: 'false' },
        },
      },
    },
  });

  assert.equal(userPk, null);
});

test('rejects an event without verified API Gateway JWT claims', () => {
  assert.equal(resolveGatewayAuthenticatedUserPk({ requestContext: {} }), null);
});

test('does not expose an application-level bearer-token verifier', () => {
  const identity = require('../auth_identity');

  assert.deepEqual(Object.keys(identity).sort(), [
    'deriveUserScopeId',
    'resolveGatewayAuthenticatedUserPk',
  ]);
});
